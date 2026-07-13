#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
out_dir="$repo_root/System/Rootfs/Generated"

version="${MIXTAR_ZSH_VERSION:-5.9.2}"
url="${MIXTAR_ZSH_URL:-https://www.zsh.org/pub/zsh-$version.tar.xz}"
work_dir="$out_dir/zsh-source"
tarball="$work_dir/zsh-$version.tar.xz"
src_dir="$work_dir/zsh-$version"
stage_dir="${MIXTAR_ZSH_STAGE:-$out_dir/zsh-source-stage}"
prefix="/System/Terminal/ZSH"

mkdir -p "$work_dir"

verified_archive="${MIXTAR_ZSH_ARCHIVE:-$repo_root/System/Shells/ZSH/$version/Dist/zsh-$version.tar.xz}"
if [[ -f "$verified_archive" ]]; then
  cp "$verified_archive" "$tarball"
fi

download_one() {
  source_url="$1"
  tmp="$tarball.tmp"
  rm -f "$tmp"
  if command -v curl >/dev/null 2>&1; then
    curl -fL "$source_url" -o "$tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$tmp" "$source_url"
  else
    printf 'zsh-build: curl or wget is required\n' >&2
    exit 1
  fi
  if file "$tmp" | grep -Eq 'XZ compressed data|XZ archive data'; then
    mv "$tmp" "$tarball"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

if [[ ! -f "$tarball" ]] || ! file "$tarball" | grep -Eq 'XZ compressed data|XZ archive data'; then
  rm -f "$tarball"
  urls=()
  if [[ -n "$url" ]]; then
    urls+=("$url")
  fi
  urls+=(
    "https://www.zsh.org/pub/zsh-$version.tar.xz"
    "https://www.zsh.org/pub/old/zsh-$version.tar.xz"
    "https://downloads.sourceforge.net/project/zsh/zsh/$version/zsh-$version.tar.xz"
    "https://sourceforge.net/projects/zsh/files/zsh/$version/zsh-$version.tar.xz/download"
  )
  downloaded=0
  for candidate_url in "${urls[@]}"; do
    if download_one "$candidate_url"; then
      downloaded=1
      break
    fi
  done
  if [[ "$downloaded" != "1" ]]; then
    printf 'zsh-build: could not download zsh %s source archive\n' "$version" >&2
    exit 1
  fi
fi

rm -rf "$src_dir" "$stage_dir"
tar -xJf "$tarball" -C "$work_dir"

(
  cd "$src_dir"
  ./configure \
    --prefix="$prefix" \
    --bindir="$prefix" \
    --libdir="$prefix/Modules" \
    --datadir="$prefix/Share" \
    --mandir="$prefix/Documentation/man" \
    --infodir="$prefix/Documentation/info" \
    --enable-function-subdirs \
    --enable-fndir="$prefix/Functions" \
    --enable-site-fndir="$prefix/Functions/Site" \
    --enable-scriptdir="$prefix/Scripts" \
        --enable-etcdir=/System/Shells \
        --enable-zshenv=/System/Shells/zshenv \
    --enable-multibyte
  perl -0pi -e 's/name=zsh\/termcap modfile=Src\/Modules\/termcap\.mdd link=\S+ auto=\S+ load=\S+/name=zsh\/termcap modfile=Src\/Modules\/termcap.mdd link=no auto=no load=no/' config.modules
  make -j"$(nproc)"
  make install DESTDIR="$stage_dir"
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
  printf 'zsh-build: dynamic loader was not staged\n' >&2
  exit 1
fi

if [[ -d "$stage_dir$prefix/Functions" ]]; then
  find "$stage_dir$prefix/Functions" -type f -name '*.zwc' -delete
  find "$stage_dir$prefix/Functions" -type f -exec sed -i 's#/dev/null#/System/Devices/null#g' {} +
fi

if command -v strip >/dev/null 2>&1; then
  find "$stage_dir$prefix" -type f -perm -111 -exec strip {} + 2>/dev/null || true
fi

if ! command -v patchelf >/dev/null 2>&1; then
  printf 'zsh-build: patchelf is required\n' >&2
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
name=ZSH
version=$version
source=$url
prefix=$prefix
runtime=$prefix/Runtime
config=/System/Configuration/Settings/ZSH/ZSH.config
EOF

printf 'zsh-build: staged %s\n' "$stage_dir"
