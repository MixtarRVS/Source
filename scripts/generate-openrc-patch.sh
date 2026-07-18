#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/mixtar"
SOURCE=${1:-"$CACHE_ROOT/openrc/prepared-source"}
OUTPUT=${2:-"$REPO_ROOT/Patches/OpenRC/0001-mixtar-layout.patch"}

cd "$SOURCE"
git init -q
git add \
  src/openrc-init/openrc-init.c \
  src/librc/rc.h.in \
  src/librc/meson.build \
  src/shared/rc_exec.c \
  src/openrc/rc.c
git -c user.name=Mixtar -c user.email=builder@mixtar.invalid \
  commit -qm baseline

sed -i 's|/sbin:/usr/sbin:/bin:/usr/bin|/System/Init:/System/Commands:/System/Terminal/ZSH|' \
  src/openrc-init/openrc-init.c
sed -i 's|shell = "/bin/sh";|shell = "/System/Terminal/ZSH/zsh";|' \
  src/openrc-init/openrc-init.c
sed -i 's|"/run/openrc"|"/System/Runtime/OpenRC"|' src/librc/rc.h.in
sed -i "s|'/run/openrc'|'/System/Runtime/OpenRC'|" src/librc/meson.build
sed -i 's|"/dev/null"|"/System/Devices/null"|' src/shared/rc_exec.c
sed -i 's|"/dev/.rcboot"|"/System/Runtime/OpenRC/.boot"|' src/openrc/rc.c

git diff --binary -- \
  src/openrc-init/openrc-init.c \
  src/librc/rc.h.in \
  src/librc/meson.build \
  src/shared/rc_exec.c \
  src/openrc/rc.c > "$OUTPUT"
