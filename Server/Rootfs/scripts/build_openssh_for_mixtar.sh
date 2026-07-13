#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
out_dir="$repo_root/Server/Rootfs/Generated"

version="${MIXTAR_OPENSSH_VERSION:-10.3p1}"
url="${MIXTAR_OPENSSH_URL:-https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-$version.tar.gz}"
work_dir="$out_dir/openssh-source"
tarball="$work_dir/openssh-$version.tar.gz"
src_dir="$work_dir/openssh-$version"
stage_dir="${MIXTAR_OPENSSH_STAGE:-$out_dir/openssh-source-stage}"
prefix="/System/Networking/SSH"

mkdir -p "$work_dir"

if [[ ! -f "$tarball" ]]; then
  if command -v curl >/dev/null 2>&1; then
    curl -L "$url" -o "$tarball"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$tarball" "$url"
  else
    printf 'openssh-build: curl or wget is required\n' >&2
    exit 1
  fi
fi

rm -rf "$src_dir" "$stage_dir"
tar -xzf "$tarball" -C "$work_dir"

(
  cd "$src_dir"
  ./configure \
    --prefix="$prefix" \
    --bindir="$prefix/bin" \
    --sbindir="$prefix/sbin" \
    --libexecdir="$prefix/libexec" \
    --sysconfdir=/System/Configuration/SSH \
    --localstatedir=/System/Runtime/Networking/SSH \
    --with-pid-dir=/System/Runtime/Networking/SSH \
    --with-privsep-path=/System/Runtime/Networking/SSH/empty \
    --without-pam \
    --without-kerberos5 \
    --without-libedit
  make -j"$(nproc)"
  make install-nokeys DESTDIR="$stage_dir"
)

runtime_dir="$stage_dir$prefix/Runtime"
mkdir -p "$runtime_dir"

copy_runtime() {
  elf="$1"
  if [[ ! -e "$elf" ]]; then
    return
  fi
  ldd "$elf" 2>/dev/null | awk '
    /^[[:space:]]*\// { print $1; next }
    /=>[[:space:]]*\// { print $3; next }
  ' | sort -u | while read -r lib; do
    if [[ -e "$lib" ]]; then
      cp -L "$lib" "$runtime_dir/$(basename "$lib")"
    fi
  done
}

while IFS= read -r -d '' elf; do
  if file "$elf" | grep -q 'ELF'; then
    copy_runtime "$elf"
  fi
done < <(find "$stage_dir$prefix" -type f -print0)

if [[ ! -f "$runtime_dir/ld-linux-x86-64.so.2" ]]; then
  for loader in /lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2; do
    if [[ -f "$loader" ]]; then
      cp -L "$loader" "$runtime_dir/ld-linux-x86-64.so.2"
      break
    fi
  done
fi

if [[ ! -f "$runtime_dir/ld-linux-x86-64.so.2" ]]; then
  printf 'openssh-build: dynamic loader was not staged\n' >&2
  exit 1
fi

if command -v strip >/dev/null 2>&1; then
  find "$stage_dir$prefix" -type f -perm -111 -exec strip {} + 2>/dev/null || true
fi

if ! command -v patchelf >/dev/null 2>&1; then
  printf 'openssh-build: patchelf is required\n' >&2
  exit 1
fi

while IFS= read -r -d '' elf; do
  if file "$elf" | grep -q 'ELF'; then
    if patchelf --print-interpreter "$elf" >/dev/null 2>&1; then
      patchelf --set-interpreter "$prefix/Runtime/ld-linux-x86-64.so.2" "$elf"
      patchelf --set-rpath "$prefix/Runtime" "$elf" 2>/dev/null || true
    fi
  fi
done < <(find "$stage_dir$prefix" -type f -print0)

cat > "$stage_dir$prefix/source.manifest" <<EOF
name=OpenSSH
version=$version
source=$url
prefix=$prefix
sysconfdir=/System/Configuration/SSH
runtime=$prefix/Runtime
installed_tools=ssh,sshd,scp,sftp,ssh-keygen,ssh-keyscan,ssh-agent,ssh-add,sftp-server
EOF

printf 'openssh-build: staged %s\n' "$stage_dir"
