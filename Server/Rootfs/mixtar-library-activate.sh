#!/bin/sh
set -eu

libraries_dir="/System/Libraries"
config_dir="/System/Config/MixtarRVS"
loader_path="/etc/ld-musl-x86_64.path"
backup_path="$config_dir/ld-musl-x86_64.path.previous"
active_record="$config_dir/ld-musl-x86_64.path.active"
report="$config_dir/runtime-library-activation-report.txt"

line() {
  printf '%s\n' "$*"
}

require_file() {
  path="$1"
  if [ ! -e "$path" ]; then
    line "missing required file: $path" >&2
    exit 2
  fi
}

test_command() {
  label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    line "ok: $label"
    return 0
  fi
  line "fail: $label"
  return 1
}

mkdir -p "$config_dir"

if [ ! -d "$libraries_dir" ]; then
  line "missing libraries directory: $libraries_dir" >&2
  exit 2
fi

require_file "$libraries_dir/ld-musl-x86_64.so.1"
require_file "$libraries_dir/libfts.so.0"

if [ -e "$loader_path" ] && [ ! -e "$backup_path" ]; then
  cp -p "$loader_path" "$backup_path"
fi

cat > "$loader_path" <<'PATHEOF'
/System/Libraries
/lib
/usr/local/lib
/usr/lib
PATHEOF

cp -p "$loader_path" "$active_record"

{
  line "MixtarRVS runtime library activation"
  line "loader_path: $loader_path"
  line "active_path:"
  sed 's/^/  /' "$loader_path"
  line ""
  line "Runtime tests without LD_LIBRARY_PATH:"
  fail=0
  test_command "mixtar uname" /System/Tools/MixtarRVS/bin/uname -m || fail=1
  test_command "mixtar ls" /System/Tools/MixtarRVS/bin/ls /System || fail=1
  test_command "mixtar grep" /System/Tools/MixtarRVS/bin/grep Mixtar /etc/motd || fail=1
  test_command "mixtar sort" /System/Tools/MixtarRVS/bin/sort /System/Config/MixtarRVS/runtime-library-closure.manifest || fail=1
  line ""
  line "ldd evidence:"
  ldd /System/Tools/MixtarRVS/bin/ls 2>/dev/null | sed 's/^/  /' || true
  line ""
  if [ "$fail" -eq 0 ]; then
    line "status: PASS"
  else
    line "status: FAIL"
  fi
} > "$report"

cat "$report"
exit "$fail"
