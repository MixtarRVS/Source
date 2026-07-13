#!/bin/sh
set -eu

tools_dir="/System/Tools/MixtarRVS/bin"
libraries_dir="/System/Libraries"
config_dir="/System/Config/MixtarRVS"
required_list="$config_dir/runtime-library-required-paths.txt"
manifest="$config_dir/runtime-library-closure.manifest"
report="$config_dir/runtime-library-closure-report.txt"
tmp_required="$config_dir/runtime-library-required-paths.tmp"

line() {
  printf '%s\n' "$*"
}

collect_binary() {
  bin="$1"
  if [ ! -x "$bin" ]; then
    return
  fi

  ldd "$bin" 2>/dev/null | while IFS= read -r dep_line; do
    for field in $dep_line; do
      case "$field" in
        /*)
          if [ -e "$field" ]; then
            line "$field"
          fi
          ;;
      esac
    done
  done
}

copy_library() {
  src="$1"
  if [ ! -e "$src" ]; then
    return
  fi

  base=$(basename "$src")
  resolved=$(readlink -f "$src" 2>/dev/null || line "$src")
  target="$libraries_dir/$base"
  resolved_target=""
  if [ -e "$target" ] || [ -L "$target" ]; then
    resolved_target=$(readlink -f "$target" 2>/dev/null || true)
  fi

  if [ -n "$resolved_target" ] && [ "$resolved" = "$resolved_target" ]; then
    return
  fi

  if [ -e "$resolved" ]; then
    command cp -p "$resolved" "$libraries_dir/$(basename "$resolved")"
  fi

  command cp -Pp "$src" "$libraries_dir/$base"
}

test_with_system_libraries() {
  label="$1"
  shift
  if LD_LIBRARY_PATH="$libraries_dir" "$@" >/dev/null 2>&1; then
    line "ok: $label"
    return 0
  fi
  line "fail: $label"
  return 1
}

mkdir -p "$config_dir"
if [ -L "$libraries_dir" ]; then
  libraries_target=$(readlink "$libraries_dir")
  case "$libraries_target" in
    ../lib|/lib)
      rm -f "$libraries_dir"
      mkdir -p "$libraries_dir"
      ;;
    *)
      line "refusing to replace unexpected $libraries_dir link -> $libraries_target" >&2
      exit 2
      ;;
  esac
elif [ -d "$libraries_dir" ]; then
  :
elif [ -e "$libraries_dir" ]; then
  line "refusing to replace non-directory $libraries_dir" >&2
  exit 2
else
  mkdir -p "$libraries_dir"
fi
: > "$tmp_required"

if [ -d "$tools_dir" ]; then
  find "$tools_dir" -type f -perm -111 | while IFS= read -r bin; do
    collect_binary "$bin"
  done >> "$tmp_required"
fi

for bin in \
  /bin/sh \
  /sbin/init \
  /sbin/openrc \
  /usr/sbin/sshd \
  /sbin/dhcpcd \
  /usr/libexec/iwd \
  /usr/bin/dbus-daemon
do
  collect_binary "$bin" >> "$tmp_required"
done

sort -u "$tmp_required" > "$required_list"
rm -f "$tmp_required"

while IFS= read -r lib_path; do
  copy_library "$lib_path"
done < "$required_list"

: > "$manifest"
for copied in "$libraries_dir"/*; do
  if [ -e "$copied" ] || [ -L "$copied" ]; then
    line "$(basename "$copied")" >> "$manifest"
  fi
done
sort -u "$manifest" > "$manifest.tmp"
mv "$manifest.tmp" "$manifest"

cat > "$config_dir/ld-musl-x86_64.path.proposed" <<'PATHEOF'
/System/Libraries
/lib
/usr/local/lib
/usr/lib
PATHEOF

{
  line "MixtarRVS runtime library closure"
  line "libraries_dir: $libraries_dir"
  line "required_paths: $(wc -l < "$required_list" | tr -d ' ')"
  line "copied_entries: $(wc -l < "$manifest" | tr -d ' ')"
  line ""
  line "Required source paths:"
  sed 's/^/  /' "$required_list"
  line ""
  line "Copied /System/Libraries entries:"
  sed 's/^/  /' "$manifest"
  line ""
  line "Runtime tests with LD_LIBRARY_PATH=/System/Libraries:"
  fail=0
  test_with_system_libraries "mixtar uname" /System/Tools/MixtarRVS/bin/uname -m || fail=1
  test_with_system_libraries "mixtar ls" /System/Tools/MixtarRVS/bin/ls /System || fail=1
  test_with_system_libraries "mixtar grep" /System/Tools/MixtarRVS/bin/grep Mixtar /etc/motd || fail=1
  test_with_system_libraries "mixtar sort" /System/Tools/MixtarRVS/bin/sort "$manifest" || fail=1
  line ""
  if [ "$fail" -eq 0 ]; then
    line "status: PASS"
  else
    line "status: FAIL"
  fi
} > "$report"

cat "$report"
exit "$fail"
