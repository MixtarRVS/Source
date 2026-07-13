#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

rootfs_dir="$repo_root/Server/Rootfs/Generated/initramfs-root"
out_dir="$repo_root/Server/Rootfs/Generated"
init_src="$repo_root/Server/Rootfs/initramfs/mixtar_init.c"
ail_init_src="$repo_root/Server/Rootfs/initramfs/mixtar_init.ail"
ailang_root="${AILANG_ROOT:-$repo_root/../AILang-Pure}"
tool_dir="$repo_root/Server/Userland/Generated/targets/linux-x64/bin"
msh_bin="$repo_root/out/server/msh_cli"
image="$out_dir/mixtar-initramfs.cpio.gz"
read -r -a mixtar_pid1_cflags <<< "${MIXTAR_PID1_CFLAGS:--O3 -flto -static -ffunction-sections -fdata-sections -Wl,--gc-sections -DNDEBUG -Wall -Wextra -Werror}"
read -r -a mixtar_pid1_cxxflags <<< "${MIXTAR_PID1_CXXFLAGS:--std=c++23 -O3 -flto -static -ffunction-sections -fdata-sections -Wl,--gc-sections -DNDEBUG -Wall -Wextra -Werror}"
read -r -a mixtar_ail_pid1_cflags <<< "${MIXTAR_AIL_PID1_CFLAGS:--O3 -flto -static -ffunction-sections -fdata-sections -Wl,--gc-sections -DAILANG_TRACK_ALLOCATIONS=0 -DNDEBUG -Wall -Wextra -Werror}"
shadow_tool="$repo_root/Server/Auth/tools/provision_rootfs_shadow.py"

rm -rf "$rootfs_dir"
mkdir -p "$rootfs_dir"/{dev,proc,sys,usr,var}
mkdir -p "$rootfs_dir"/{Applications,Programs,Users,Temporary}
mkdir -p "$rootfs_dir"/Users/Administrator
mkdir -p "$rootfs_dir"/System/{Config,Init,Kernel,Libraries,Logs,Resources,Runtime/run,Shells,SystemTools,Tools}

cc "${mixtar_pid1_cflags[@]}" -o "$rootfs_dir/System/Init/Mixtar" "$init_src"
chmod 0755 "$rootfs_dir/System/Init/Mixtar"

if command -v g++ >/dev/null 2>&1; then
  g++ -x c++ "${mixtar_pid1_cxxflags[@]}" \
    -o "$rootfs_dir/System/Init/MixtarCxx" "$init_src"
  chmod 0755 "$rootfs_dir/System/Init/MixtarCxx"
else
  echo "rootfs-build: warning: g++ missing; C++ init candidate not built" >&2
fi

if [[ -f "$ail_init_src" && -f "$ailang_root/ailang.py" ]]; then
  python3 "$ailang_root/ailang.py" "$ail_init_src" --emit-c \
    -o "$out_dir/mixtar_init_ail.c"
  cc "${mixtar_ail_pid1_cflags[@]}" \
    -o "$rootfs_dir/System/Init/MixtarAil" "$out_dir/mixtar_init_ail.c"
  chmod 0755 "$rootfs_dir/System/Init/MixtarAil"
else
  echo "rootfs-build: warning: AILang init candidate not built" >&2
fi

ln -s System/Init/Mixtar "$rootfs_dir/init"
ln -s System/Tools "$rootfs_dir/bin"
ln -s System/SystemTools "$rootfs_dir/sbin"
ln -s System/Libraries "$rootfs_dir/lib"
ln -s System/Libraries "$rootfs_dir/lib64"
ln -s System/Config "$rootfs_dir/etc"
ln -s Users "$rootfs_dir/home"
ln -s Users/Administrator "$rootfs_dir/root"
ln -s Administrator "$rootfs_dir/Users/Superuser"
ln -s Administrator "$rootfs_dir/Users/root"
ln -s Temporary "$rootfs_dir/tmp"
ln -s ../System/Tools "$rootfs_dir/usr/bin"
ln -s ../System/SystemTools "$rootfs_dir/usr/sbin"
ln -s ../System/Libraries "$rootfs_dir/usr/lib"
ln -s ../System/Resources "$rootfs_dir/usr/share"
ln -s ../System/Logs "$rootfs_dir/var/log"
ln -s ../System/Runtime/run "$rootfs_dir/var/run"

copy_runtime_file() {
  local src="$1"
  local rel="${src#/}"

  case "$src" in
    /lib/*)
      rel="System/Libraries/${src#/lib/}"
      ;;
    /lib64/*)
      rel="System/Libraries/${src#/lib64/}"
      ;;
    /usr/lib/*)
      rel="System/Libraries/${src#/usr/lib/}"
      ;;
  esac

  mkdir -p "$rootfs_dir/$(dirname "$rel")"
  cp -n "$src" "$rootfs_dir/$rel"
}

copy_runtime_deps() {
  local binary="$1"
  ldd "$binary" 2>/dev/null |
      awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i }' |
      while IFS= read -r lib; do
        [[ -e "$lib" ]] || continue
        copy_runtime_file "$lib"
      done
}

copy_tool() {
  local name="$1"
  if [[ -x "$tool_dir/$name" ]]; then
    cp "$tool_dir/$name" "$rootfs_dir/System/Tools/$name"
    chmod 0755 "$rootfs_dir/System/Tools/$name"
    copy_runtime_deps "$tool_dir/$name"
  else
    echo "rootfs-build: warning: missing toolkit tool $name" >&2
  fi
}

for tool in echo cat ls pwd true false uname test printf; do
  copy_tool "$tool"
done

if [[ -f "$msh_bin" ]]; then
  cp "$msh_bin" "$rootfs_dir/System/Shells/msh"
  chmod 0755 "$rootfs_dir/System/Shells/msh"
  ln -s ../Shells/msh "$rootfs_dir/System/Tools/sh"
  copy_runtime_deps "$msh_bin"
else
  echo "rootfs-build: warning: missing msh linux binary $msh_bin" >&2
fi

cat > "$rootfs_dir/System/Config/mixtar-release" <<'EOF'
NAME=MixtarRVS Server
STAGE=v0-rootfs-proof
USERLAND=OpenBSD-first Toolkit Tier A
ADMIN_USER=Administrator
SUPERUSER_ALIAS=Superuser
EOF

cat > "$rootfs_dir/System/Config/passwd" <<'EOF'
Administrator:x:0:0:Mixtar Administrator:/Users/Administrator:/System/Shells/msh
Superuser:x:0:0:Administrator alias:/Users/Administrator:/System/Shells/msh
EOF

cat > "$rootfs_dir/System/Config/group" <<'EOF'
Administrator:x:0:Administrator,Superuser
EOF

if [[ -n "${MIXTAR_ADMIN_PASSWORD_HASH_FILE:-}" ]]; then
  python3 "$shadow_tool" --rootfs "$rootfs_dir" \
    --hash-file "$MIXTAR_ADMIN_PASSWORD_HASH_FILE" --quiet
elif [[ -n "${MIXTAR_ADMIN_PASSWORD_HASH:-}" ]]; then
  python3 "$shadow_tool" --rootfs "$rootfs_dir" \
    --hash-env MIXTAR_ADMIN_PASSWORD_HASH --quiet
else
  python3 "$shadow_tool" --rootfs "$rootfs_dir" --locked --quiet
fi

cat > "$rootfs_dir/System/Init/boot-smoke.sh" <<'EOF'
#!/System/Shells/msh
echo boot-smoke: script placeholder
EOF
chmod 0755 "$rootfs_dir/System/Init/boot-smoke.sh"

mkdir -p "$out_dir"
(
  cd "$rootfs_dir"
  find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9
) > "$image"

printf 'rootfs-build: wrote %s\n' "$image"
printf 'rootfs-build: root %s\n' "$rootfs_dir"
