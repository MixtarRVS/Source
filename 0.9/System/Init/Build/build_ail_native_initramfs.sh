#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

out_dir="${MIXTAR_GENERATED_DIR:-$repo_root/Server/Rootfs/Generated}"
rootfs_dir="$out_dir/ail-native-initramfs-root"
image="$out_dir/mixtar-ail-native-initramfs.cpio.gz"
boot_image="$out_dir/mixtar-boot-initramfs.cpio"
ail_init_src="$repo_root/Server/Rootfs/initramfs/mixtar_init.ail"
ail_boot_src="$repo_root/Server/Rootfs/initramfs/mixtar_boot.ail"
ail_init_verify_src="$repo_root/Server/Rootfs/initramfs/mixtar_init_verify.ail"
console_setup_src="$repo_root/Server/Rootfs/initramfs/mixtar_console_setup.c"
ailang_root="${AILANG_ROOT:-$repo_root/../AILang-Pure}"
generated_c="$out_dir/mixtar_init_native_ail.c"
generated_boot_c="$out_dir/mixtar_boot_native_ail.c"
verifier_bin="$out_dir/mixtar_init_verify"
sqlite_pid1_dir="$out_dir/sqlite-pid1"
sqlite_pid1_zip="$sqlite_pid1_dir/sqlite-amalgamation.zip"
sqlite_pid1_url="${MIXTAR_PID1_SQLITE_URL:-https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip}"
sqlite_pid1_c="${MIXTAR_PID1_SQLITE_C:-$sqlite_pid1_dir/sqlite3.c}"
sqlite_pid1_o="$sqlite_pid1_dir/sqlite3-pid1.o"

build_boot_initramfs() (
  boot_root=$(mktemp -d /tmp/mixtar-boot-initramfs.XXXXXX)
  case "$boot_root" in
    /tmp/mixtar-boot-initramfs.*) ;;
    *) printf 'ail-native-build: unsafe boot root: %s\n' "$boot_root" >&2; exit 1 ;;
  esac
  trap 'rm -rf -- "$boot_root"' EXIT HUP INT TERM
  mkdir -p \
    "$boot_root/System/Devices" \
    "$boot_root/System/Hardware" \
    "$boot_root/System/Init" \
    "$boot_root/System/Process" \
    "$boot_root/System/Runtime/Root"
  install -m 0755 "$rootfs_dir/System/Init/MixtarBoot" \
    "$boot_root/System/Init/MixtarBoot"
  find "$boot_root" -exec touch -h -d '@0' {} +
  (
    cd "$boot_root"
    find . -print0 | LC_ALL=C sort -z | \
      cpio --null -o --format=newc --owner=0:0 --reproducible 2>/dev/null
  ) > "$boot_image"
  cpio -it < "$boot_image" 2>/dev/null | \
    grep -qx 'System/Init/MixtarBoot' || {
      printf 'ail-native-build: boot initramfs is missing MixtarBoot\n' >&2
      exit 1
    }
)
openssh_stage_dir="${MIXTAR_OPENSSH_STAGE:-$out_dir/openssh-source-stage}"
zsh_stage_dir="${MIXTAR_ZSH_STAGE:-$out_dir/zsh-source-stage}"
wifi_source_dir="${MIXTAR_WIFI_SOURCE:-$out_dir/wifi-source/root}"
system_name="${MIXTAR_SYSTEM_NAME:-MixtarRVS}"
default_user="${MIXTAR_DEFAULT_USER:-Administrator}"
admin_user="${MIXTAR_ADMIN_USER:-Administrator}"
authorized_keys_source="${MIXTAR_AUTHORIZED_KEYS:-}"
pid1_profile="${MIXTAR_AIL_PID1_PROFILE:-musl-static}"
case "$pid1_profile" in
  musl-static)
    default_cc="musl-gcc"
    default_cflags="-O2 -static -ffunction-sections -fdata-sections -Wl,--gc-sections -DAILANG_TRACK_ALLOCATIONS=0 -DNDEBUG -Wall -Wextra -Werror -I$sqlite_pid1_dir"
    default_sqlite_cflags="-O2 -DSQLITE_OMIT_LOAD_EXTENSION=1 -DSQLITE_THREADSAFE=0 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DQS=0 -DSQLITE_OMIT_DEPRECATED=1 -DSQLITE_OMIT_SHARED_CACHE=1"
    default_ldflags="-lm"
    ;;
  glibc-static)
    default_cc="cc"
    default_cflags="-O3 -flto -static -ffunction-sections -fdata-sections -Wl,--gc-sections -DAILANG_TRACK_ALLOCATIONS=0 -DNDEBUG -Wall -Wextra -Werror -I$sqlite_pid1_dir"
    default_sqlite_cflags="-O2 -DSQLITE_OMIT_LOAD_EXTENSION=1 -DSQLITE_THREADSAFE=0 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DQS=0 -DSQLITE_OMIT_DEPRECATED=1 -DSQLITE_OMIT_SHARED_CACHE=1"
    default_ldflags="-lm"
    ;;
  *)
    printf 'ail-native-build: unknown MIXTAR_AIL_PID1_PROFILE=%s\n' "$pid1_profile" >&2
    printf 'ail-native-build: supported profiles: musl-static glibc-static\n' >&2
    exit 1
    ;;
esac
cc_bin="${CC:-$default_cc}"
read -r -a cflags <<< "${MIXTAR_AIL_PID1_CFLAGS:-$default_cflags}"
read -r -a sqlite_cflags <<< "${MIXTAR_PID1_SQLITE_CFLAGS:-$default_sqlite_cflags}"
read -r -a ldflags <<< "${MIXTAR_AIL_PID1_LDFLAGS:-$default_ldflags}"

prepare_pid1_sqlite() {
  mkdir -p "$sqlite_pid1_dir"
  if [[ ! -f "$sqlite_pid1_c" ]]; then
    python3 - "$sqlite_pid1_url" "$sqlite_pid1_zip" "$sqlite_pid1_dir" <<'PY'
import pathlib
import sys
import urllib.request
import zipfile

url = sys.argv[1]
zip_path = pathlib.Path(sys.argv[2])
out_dir = pathlib.Path(sys.argv[3])

zip_path.parent.mkdir(parents=True, exist_ok=True)
urllib.request.urlretrieve(url, zip_path)
with zipfile.ZipFile(zip_path) as archive:
    for member in archive.namelist():
        name = pathlib.PurePosixPath(member).name
        if name in {"sqlite3.c", "sqlite3.h"}:
            (out_dir / name).write_bytes(archive.read(member))
PY
  fi
  if [[ ! -f "$sqlite_pid1_c" ]]; then
    printf 'ail-native-build: missing PID1 sqlite amalgamation: %s\n' "$sqlite_pid1_c" >&2
    exit 1
  fi
  if [[ -f "$sqlite_pid1_o" && "$sqlite_pid1_o" -nt "$sqlite_pid1_c" ]]; then
    return 0
  fi
  sqlite_temp_o="${TMPDIR:-/tmp}/mixtar-sqlite-pid1.$$.o"
  if ! "$cc_bin" "${sqlite_cflags[@]}" -I"$sqlite_pid1_dir" -c "$sqlite_pid1_c" -o "$sqlite_temp_o"; then
    rm -f -- "$sqlite_temp_o"
    return 1
  fi
  cp "$sqlite_temp_o" "$sqlite_pid1_o"
  rm -f -- "$sqlite_temp_o"
}

build_init_tools() {
  tools_dir="$rootfs_dir/System/Userland"
  tools_log_dir="$out_dir/init-tools/logs"
  mkdir -p "$tools_dir" "$tools_log_dir"
  musl_userland_dir="$repo_root/out/mixtarrvs-musl-target/bin"
  if [[ -d "$musl_userland_dir" ]]; then
    find "$musl_userland_dir" -maxdepth 1 -type f -executable -exec cp -t "$tools_dir" -- {} +
    chmod 0755 "$tools_dir"/*
    if command -v strip >/dev/null 2>&1; then
      strip "$tools_dir"/* 2>/dev/null || true
    fi
    find "$tools_dir" -maxdepth 1 -type f -executable -printf '%f\n' | sort > "$rootfs_dir/System/Configuration/userland-tools.txt"
    return
  fi
  tool_common=(
    -std=c23
    -Wno-unterminated-string-initialization
    -Wall
    -Wextra
    -Werror
    -pedantic
    -D_GNU_SOURCE
    -D_DEFAULT_SOURCE
    -I "$repo_root/Server/Userland/Toolkit/Bridge/include"
    -DMIXTAR_BRIDGE=1
    -include "$repo_root/Server/Userland/Toolkit/Bridge/include/mixtar_bridge_compat.h"
  )
  "$cc_bin" -static "${tool_common[@]}" \
    -o "$tools_dir/echo" \
    "$repo_root/Server/Userland/Toolkit/FreeBSD/freebsd-src/bin/echo/echo.c" \
    "$repo_root/Server/Runtime/LibC/Generated/bsd_compat.c" \
    >"$tools_log_dir/echo.log" 2>&1
  "$cc_bin" -static "${tool_common[@]}" -DNO_UDOM_SUPPORT -DBOOTSTRAP_CAT \
    -o "$tools_dir/cat" \
    "$repo_root/Server/Userland/Toolkit/FreeBSD/freebsd-src/bin/cat/cat.c" \
    "$repo_root/Server/Runtime/LibC/Generated/bsd_compat.c" \
    >"$tools_log_dir/cat.log" 2>&1
  "$cc_bin" -static "${tool_common[@]}" \
    -o "$tools_dir/pwd" \
    "$repo_root/Server/Userland/Toolkit/OpenBSD/src/bin/pwd/pwd.c" \
    "$repo_root/Server/Runtime/LibC/Generated/bsd_compat.c" \
    >"$tools_log_dir/pwd.log" 2>&1
  "$cc_bin" -static "${tool_common[@]}" -Wno-format -Wno-implicit-fallthrough \
    -o "$tools_dir/ls" \
    "$repo_root/Server/Userland/Toolkit/FreeBSD/freebsd-src/bin/ls/ls.c" \
    "$repo_root/Server/Userland/Toolkit/FreeBSD/freebsd-src/bin/ls/cmp.c" \
    "$repo_root/Server/Userland/Toolkit/FreeBSD/freebsd-src/bin/ls/print.c" \
    "$repo_root/Server/Userland/Toolkit/FreeBSD/freebsd-src/bin/ls/util.c" \
    "$repo_root/Server/Runtime/LibC/Generated/bsd_compat.c" \
    >"$tools_log_dir/ls.log" 2>&1
  chmod 0755 "$tools_dir/echo" "$tools_dir/cat" "$tools_dir/pwd" "$tools_dir/ls"
}

build_zsh_terminal() {
  terminal_dir="$rootfs_dir/System/Terminal/ZSH"
  runtime_dir="$terminal_dir/Runtime"
  functions_dir="$terminal_dir/Functions"
  terminfo_dir="$terminal_dir/Terminfo"
  grml_dir="$terminal_dir/grml"

  if [[ ! -x "$zsh_stage_dir/System/Terminal/ZSH/zsh" ]]; then
    bash "$script_dir/build_zsh_for_mixtar.sh"
  fi

  if [[ ! -x "$zsh_stage_dir/System/Terminal/ZSH/zsh" ]]; then
    printf 'ail-native-build: missing source-built ZSH: %s\n' "$zsh_stage_dir/System/Terminal/ZSH/zsh" >&2
    exit 1
  fi

  rm -rf "$terminal_dir"
  mkdir -p "$terminal_dir"
  cp -a "$zsh_stage_dir/System/Terminal/ZSH/." "$terminal_dir/"
  mkdir -p "$runtime_dir" "$functions_dir" "$terminfo_dir" "$grml_dir"

  patch_elf_tree_runtime "$terminal_dir" \
    /System/Terminal/ZSH/Runtime/ld-linux-x86-64.so.2 \
    /System/Terminal/ZSH/Runtime

  if [[ -d "$functions_dir" ]]; then
    find "$functions_dir" -type f -name '*.zwc' -delete
    find "$functions_dir" -type f -exec sed -i 's#/dev/null#/System/Devices/null#g' {} +
    for bootstrap_fn in compinit compdump; do
      if [[ -f "$functions_dir/Completion/$bootstrap_fn" ]]; then
        cp "$functions_dir/Completion/$bootstrap_fn" "$functions_dir/$bootstrap_fn"
      fi
    done
  fi

  for term in linux xterm xterm-256color vt100 ansi dumb; do
    first="${term:0:1}"
    for base in /usr/share/terminfo /lib/terminfo; do
      if [[ -f "$base/$first/$term" ]]; then
        mkdir -p "$terminfo_dir/$first"
        cp "$base/$first/$term" "$terminfo_dir/$first/$term"
        break
      fi
    done
  done

  cat > "$grml_dir/mixtar-grml.zsh" <<'ZSH'
export PATH=/System/Terminal/ZSH:/System/Userland
export HISTFILE=/System/Runtime/Terminal/ZSH/history
export SAVEHIST=5000
export HISTSIZE=5000
export ZSH_COMPDUMP=/System/Runtime/Terminal/ZSH/.zcompdump

module_path=(/System/Terminal/ZSH/Modules $module_path)
fpath=(
  /System/Terminal/ZSH/Functions
  /System/Terminal/ZSH/Functions/Completion
  /System/Terminal/ZSH/Functions/Completion/Base
  /System/Terminal/ZSH/Functions/Completion/Linux
  /System/Terminal/ZSH/Functions/Completion/Unix
  /System/Terminal/ZSH/Functions/Completion/Zsh
  /System/Terminal/ZSH/Functions/Misc
  /System/Terminal/ZSH/Functions/Prompts
  $fpath
)

setopt prompt_subst
unsetopt beep
PROMPT='%F{green}${USER}@${MIXTAR_SYSTEM_NAME}%f:%F{blue}%~%f> '

autoload -Uz compinit compdump
compinit -u -D
zmodload zsh/complist 2>/System/Devices/null || true

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

bindkey -e
bindkey '^?' backward-delete-char
bindkey '^H' backward-delete-char
bindkey '^[[3~' delete-char
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward
bindkey '^[[C' forward-char
bindkey '^[[D' backward-char
bindkey '^[OA' history-beginning-search-backward
bindkey '^[OB' history-beginning-search-forward
bindkey '^[OC' forward-char
bindkey '^[OD' backward-char
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[OH' beginning-of-line
bindkey '^[OF' end-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[4~' end-of-line
bindkey '^[[1;3A' up-line-or-history
bindkey '^[[1;3B' down-line-or-history
mixtar_ignore_function_key() { return 0 }
zle -N mixtar-ignore-function-key mixtar_ignore_function_key
for key_sequence in \
  '^[[[A' '^[[[B' '^[[[C' '^[[[D' '^[[[E' \
  '^[OP' '^[OQ' '^[OR' '^[OS' '^[[15~' \
  '^[[17~' '^[[18~' '^[[19~' '^[[20~' '^[[21~' '^[[23~' '^[[24~'
do
  bindkey "$key_sequence" mixtar-ignore-function-key
done
unset key_sequence
setopt auto_cd
setopt auto_list
setopt auto_menu
setopt auto_param_slash
setopt complete_in_word
setopt extended_glob
setopt hist_ignore_dups
setopt hist_reduce_blanks
setopt inc_append_history
setopt interactive_comments
setopt no_beep
ZSH

  cat > "$terminal_dir/start-zsh" <<'ZSH'
#!/System/Terminal/ZSH/zsh -f
emulate -R zsh
export PATH=/System/Terminal/ZSH:/System/Userland
export LD_LIBRARY_PATH=/System/Terminal/ZSH/Runtime
export TERMINFO=/System/Terminal/ZSH/Terminfo
export TERM=${TERM:-linux}
export USER=${USER:-vxz}
export LOGNAME=${LOGNAME:-$USER}
export HOME=${HOME:-/Users/$USER}
export MIXTAR_SYSTEM_NAME=${MIXTAR_SYSTEM_NAME:-MixtarRVS}
export ZDOTDIR=/System/Runtime/Terminal/ZSH

/System/Userland/mkdir -p /System/Runtime/Terminal/ZSH/cache

{
  print -r -- 'export PATH=/System/Terminal/ZSH:/System/Userland'
  print -r -- 'export LD_LIBRARY_PATH=/System/Terminal/ZSH/Runtime'
  print -r -- 'export TERMINFO=/System/Terminal/ZSH/Terminfo'
} > /System/Runtime/Terminal/ZSH/.zshenv

{
  print -r -- 'source /System/Terminal/ZSH/grml/mixtar-grml.zsh'
} > /System/Runtime/Terminal/ZSH/.zshrc

exec /System/Terminal/ZSH/zsh -i
ZSH

  cat > "$terminal_dir/mixtar-shutdown.c" <<'C'
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define MIXTAR_LIFECYCLE_FIFO "/System/Runtime/Lifecycle"

int main(int argc, char **argv) {
    const char *name = argc > 0 ? argv[0] : "reboot";
    const char *base = strrchr(name, '/');
    const char *request = NULL;
    size_t request_size = 0;
    base = base ? base + 1 : name;
    if (strcmp(base, "reboot") == 0) {
        request = "reboot\n";
        request_size = 7;
    } else if (strcmp(base, "poweroff") == 0) {
        request = "poweroff\n";
        request_size = 9;
    } else {
        fputs("MixtarRVS lifecycle request is invalid\n", stderr);
        return 2;
    }
    int fd = open(MIXTAR_LIFECYCLE_FIFO, O_WRONLY | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) {
        perror("MixtarRVS lifecycle request failed");
        return 1;
    }
    ssize_t written = write(fd, request, request_size);
    int close_rc = close(fd);
    if (written != (ssize_t)request_size || close_rc != 0) {
        fputs("MixtarRVS lifecycle request was not delivered\n", stderr);
        return 1;
    }
    return 0;
}
C
  "$cc_bin" "${cflags[@]}" -o "$terminal_dir/reboot" "$terminal_dir/mixtar-shutdown.c" "${ldflags[@]}"
  cp "$terminal_dir/reboot" "$terminal_dir/poweroff"
  rm -f "$terminal_dir/mixtar-shutdown.c"

  chmod 0755 "$terminal_dir/zsh" "$terminal_dir/start-zsh" "$terminal_dir/reboot" "$terminal_dir/poweroff"
  if command -v strip >/dev/null 2>&1; then
    strip "$terminal_dir/zsh" 2>/dev/null || true
    strip "$terminal_dir/reboot" "$terminal_dir/poweroff" 2>/dev/null || true
  fi
}

copy_ldd_runtime() {
  bin="$1"
  runtime_dir="$2"
  mapfile -t libs < <(
    ldd "$bin" 2>/dev/null | awk '
      /^[[:space:]]*\// { print $1; next }
      /=>[[:space:]]*\// { print $3; next }
    ' | sort -u
  )
  for lib in "${libs[@]}"; do
    if [[ -e "$lib" ]]; then
      cp -L "$lib" "$runtime_dir/"
    fi
  done
}

install_host_dynamic_binary() {
  src="$1"
  dst="$2"
  runtime_dir="$3"
  interp="$4"
  rpath="$5"
  if [[ ! -x "$src" ]]; then
    return 1
  fi
  mkdir -p "$(dirname "$dst")" "$runtime_dir"
  cp -L "$src" "$dst"
  chmod 0755 "$dst"
  copy_ldd_runtime "$src" "$runtime_dir"
  if [[ ! -f "$runtime_dir/ld-linux-x86-64.so.2" ]]; then
    for loader in /lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2; do
      if [[ -f "$loader" ]]; then
        cp -L "$loader" "$runtime_dir/ld-linux-x86-64.so.2"
        break
      fi
    done
  fi
  if command -v patchelf >/dev/null 2>&1 && [[ -f "$runtime_dir/ld-linux-x86-64.so.2" ]]; then
    patchelf --set-interpreter "$interp" --set-rpath "$rpath" "$dst" 2>/dev/null || true
  fi
  return 0
}

wrap_runtime_binary() {
  bin="$1"
  runtime="$2"
  target_real="${3:-}"
  real="${bin}.bin"
  if [[ ! -x "$bin" ]]; then
    return 1
  fi
  if [[ -z "$target_real" ]]; then
    target_real="${real#$rootfs_dir}"
  fi
  mv "$bin" "$real"
  cat > "$bin" <<EOF
#!/System/Terminal/ZSH/zsh
export LD_LIBRARY_PATH=$runtime:\${LD_LIBRARY_PATH:-}
exec $target_real "\$@"
EOF
  chmod 0755 "$bin" "$real"
}

patch_elf_tree_runtime() {
  tree="$1"
  interp="$2"
  rpath="$3"
  if ! command -v patchelf >/dev/null 2>&1; then
    printf 'ail-native-build: patchelf is required to patch ELF runtime paths\n' >&2
    exit 1
  fi
  while IFS= read -r -d '' elf; do
    if file "$elf" | grep -q 'ELF'; then
      if patchelf --print-interpreter "$elf" >/dev/null 2>&1; then
        patchelf --set-interpreter "$interp" "$elf"
        patchelf --set-rpath "$rpath" "$elf" 2>/dev/null || true
      fi
    fi
  done < <(find "$tree" -type f -print0)
}

build_wifi_mvp() {
  if [[ ! -d "$wifi_source_dir" ]]; then
    return
  fi

  wifi_dir="$rootfs_dir/System/Networking/WiFi"
  wifi_bin="$wifi_dir/bin"
  wifi_runtime="$wifi_dir/Runtime"
  wifi_root="$wifi_dir/Root"
  wifi_config_dir="$rootfs_dir/System/Configuration/Networking"
  firmware_dir="$rootfs_dir/System/Kernel/Linux/Firmware"
  kernel_dir="$rootfs_dir/System/Kernel/Linux"
  kernel_tools="$kernel_dir/Tools"
  kernel_tools_runtime="$kernel_tools/Runtime"

  mkdir -p "$wifi_bin" "$wifi_runtime" "$wifi_root/etc" "$wifi_root/var" \
    "$wifi_root/System/Networking/WiFi" "$wifi_root/System/Runtime/Networking/WiFi" \
    "$wifi_root/dev" "$wifi_root/proc" "$wifi_root/sys" "$wifi_root/run/dbus" \
    "$wifi_config_dir" "$firmware_dir" "$kernel_tools_runtime" \
    "$rootfs_dir/System/Runtime/Networking/WiFi"

  if [[ -x "$wifi_source_dir/usr/libexec/iwd" ]]; then
    cp "$wifi_source_dir/usr/libexec/iwd" "$wifi_bin/iwd"
  fi
  if [[ -x "$wifi_source_dir/usr/bin/dbus-daemon" ]]; then
    cp "$wifi_source_dir/usr/bin/dbus-daemon" "$wifi_bin/dbus-daemon"
  fi
  if [[ -d "$wifi_source_dir/usr/lib/x86_64-linux-gnu" ]]; then
    cp -a "$wifi_source_dir/usr/lib/x86_64-linux-gnu/." "$wifi_runtime/" 2>/dev/null || true
  fi
  for loader in \
    "$wifi_source_dir/lib64/ld-linux-x86-64.so.2" \
    "$wifi_source_dir/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"; do
    if [[ -f "$loader" ]]; then
      cp "$loader" "$wifi_runtime/ld-linux-x86-64.so.2"
      break
    fi
  done
  if [[ -d "$wifi_source_dir/etc/iwd" ]]; then
    mkdir -p "$wifi_root/etc/iwd"
    cp -a "$wifi_source_dir/etc/iwd/." "$wifi_root/etc/iwd/"
  fi
  if [[ -d "$wifi_source_dir/var/lib/iwd" ]]; then
    mkdir -p "$wifi_root/var/lib/iwd"
    cp -a "$wifi_source_dir/var/lib/iwd/." "$wifi_root/var/lib/iwd/"
  fi
  if compgen -G "$wifi_source_dir/lib/firmware/iwlwifi-8265-*.ucode" >/dev/null; then
    cp "$wifi_source_dir"/lib/firmware/iwlwifi-8265-*.ucode "$firmware_dir/"
    mkdir -p "$wifi_root/lib/firmware"
    cp "$wifi_source_dir"/lib/firmware/iwlwifi-8265-*.ucode "$wifi_root/lib/firmware/"
  fi
  if [[ -d "$wifi_source_dir/lib/modules" ]]; then
    mkdir -p "$kernel_dir/lib"
    rm -rf "$kernel_dir/lib/modules"
    cp -a "$wifi_source_dir/lib/modules" "$kernel_dir/lib/"
  fi
  if [[ -x "$wifi_source_dir/usr/sbin/modprobe" ]]; then
    install_host_dynamic_binary "$wifi_source_dir/usr/sbin/modprobe" "$kernel_tools/modprobe" \
      "$kernel_tools_runtime" /System/Kernel/Linux/Tools/Runtime/ld-linux-x86-64.so.2 /System/Kernel/Linux/Tools/Runtime || true
    mv "$kernel_tools/modprobe" "$kernel_tools/kmod.bin"
    cat > "$kernel_tools/modprobe-launcher.c" <<'C'
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

int main(int argc, char **argv) {
    char **next = calloc((size_t)argc + 1, sizeof(char *));
    if (next == NULL) {
        fprintf(stderr, "modprobe-launcher: calloc failed\n");
        return 127;
    }
    setenv("LD_LIBRARY_PATH", "/System/Kernel/Linux/Tools/Runtime", 1);
    next[0] = "modprobe";
    for (int i = 1; i < argc; i++) {
        next[i] = argv[i];
    }
    next[argc] = NULL;
    execve("/System/Kernel/Linux/Tools/kmod.bin", next, environ);
    fprintf(stderr, "modprobe-launcher: exec failed: %s\n", strerror(errno));
    return 127;
}
C
    "$cc_bin" "${cflags[@]}" -o "$kernel_tools/modprobe" "$kernel_tools/modprobe-launcher.c" "${ldflags[@]}"
    rm -f "$kernel_tools/modprobe-launcher.c"
    chmod 0755 "$kernel_tools/modprobe" "$kernel_tools/kmod.bin"
  fi

  if [[ ! -x "$wifi_bin/iwd" || ! -x "$wifi_bin/dbus-daemon" || ! -f "$wifi_runtime/ld-linux-x86-64.so.2" ]]; then
    printf 'ail-native-build: WiFi source exists but iwd/dbus/runtime is incomplete under %s\n' "$wifi_source_dir" >&2
    exit 1
  fi

  patch_elf_tree_runtime "$wifi_dir" \
    /System/Networking/WiFi/Runtime/ld-linux-x86-64.so.2 \
    /System/Networking/WiFi/Runtime

  cat > "$wifi_dir/dbus-system.conf" <<'DBUS'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>system</type>
  <listen>unix:path=/run/dbus/system_bus_socket</listen>
  <policy context="default">
    <allow user="*"/>
    <allow own="*"/>
    <allow send_type="method_call"/>
    <allow send_type="method_return"/>
    <allow send_type="signal"/>
    <allow receive_type="method_call"/>
    <allow receive_type="method_return"/>
    <allow receive_type="signal"/>
  </policy>
</busconfig>
DBUS
  cp "$wifi_dir/dbus-system.conf" "$wifi_root/System/Networking/WiFi/dbus-system.conf"
  cp -a "$wifi_bin" "$wifi_runtime" "$wifi_root/System/Networking/WiFi/"

  cat > "$wifi_dir/mixtar-wifi-service.c" <<'C'
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int mkdir_one(const char *path, mode_t mode) {
    if (mkdir(path, mode) == 0 || errno == EEXIST) {
        return 0;
    }
    return -1;
}

static int bind_dir(const char *source, const char *target) {
    mkdir_one(target, 0755);
    if (mount(source, target, 0, MS_BIND | MS_REC, 0) == 0 || errno == EBUSY) {
        return 0;
    }
    fprintf(stderr, "mixtar-wifi-service: bind %s -> %s failed: %s\n", source, target, strerror(errno));
    return -1;
}

int main(void) {
    const char *root = "/System/Networking/WiFi/Root";
    fprintf(stderr, "mixtar-wifi-service: preparing root\n");
    bind_dir("/System/Runtime/Networking/WiFi", "/System/Networking/WiFi/Root/System/Runtime/Networking/WiFi");
    bind_dir("/System/Devices", "/System/Networking/WiFi/Root/dev");
    bind_dir("/System/Process", "/System/Networking/WiFi/Root/proc");
    bind_dir("/System/Hardware", "/System/Networking/WiFi/Root/sys");
    if (chroot(root) != 0) {
        fprintf(stderr, "mixtar-wifi-service: chroot failed: %s\n", strerror(errno));
        return 111;
    }
    if (chdir("/") != 0) {
        fprintf(stderr, "mixtar-wifi-service: chdir failed: %s\n", strerror(errno));
        return 111;
    }
    mkdir_one("/run", 0755);
    mkdir_one("/run/dbus", 0755);
    pid_t dbus_pid = fork();
    if (dbus_pid == 0) {
        setenv("LD_LIBRARY_PATH", "/System/Networking/WiFi/Runtime", 1);
        execl(
            "/System/Networking/WiFi/bin/dbus-daemon",
            "dbus-daemon",
            "--config-file=/System/Networking/WiFi/dbus-system.conf",
            "--nofork",
            "--nopidfile",
            (char *)0
        );
        fprintf(stderr, "mixtar-wifi-service: dbus exec failed: %s\n", strerror(errno));
        _exit(127);
    }
    sleep(1);
    pid_t iwd_pid = fork();
    if (iwd_pid == 0) {
        setenv("LD_LIBRARY_PATH", "/System/Networking/WiFi/Runtime", 1);
        setenv("DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/run/dbus/system_bus_socket", 1);
        fprintf(stderr, "mixtar-wifi-service: exec iwd\n");
        execl("/System/Networking/WiFi/bin/iwd", "iwd", (char *)0);
        fprintf(stderr, "mixtar-wifi-service: iwd exec failed: %s\n", strerror(errno));
        _exit(127);
    }
    fprintf(stderr, "mixtar-wifi-service: started dbus=%ld iwd=%ld\n", (long)dbus_pid, (long)iwd_pid);
    return 0;
}
C
  "$cc_bin" "${cflags[@]}" -o "$wifi_dir/mixtar-wifi-service" "$wifi_dir/mixtar-wifi-service.c" "${ldflags[@]}"
  rm -f "$wifi_dir/mixtar-wifi-service.c"

  for profile in "$wifi_root/var/lib/iwd"/*.psk; do
    if [ -f "$profile" ] && ! grep -q '^AutoConnect=' "$profile"; then
      printf '\n[Settings]\nAutoConnect=true\n' >> "$profile"
    fi
  done
  chmod 0755 "$wifi_dir/mixtar-wifi-service" "$wifi_bin/iwd" "$wifi_bin/dbus-daemon"

  python3 - "$rootfs_dir" <<'PY'
import pathlib
import sqlite3
import sys

root = pathlib.Path(sys.argv[1])
path = root / "System/Configuration/Networking/WiFi.config"
if path.exists():
    path.unlink()
db = sqlite3.connect(path)
db.executescript(
    """
    PRAGMA page_size=1024;
    PRAGMA journal_mode=OFF;
    PRAGMA synchronous=OFF;
    CREATE TABLE setting(key TEXT PRIMARY KEY, value TEXT NOT NULL);
    """
)
rows = [
    ("wifi.backend", "iwd"),
    ("wifi.service", "/System/Networking/WiFi/mixtar-wifi-service"),
    ("wifi.root", "/System/Networking/WiFi/Root"),
    ("wifi.firmware", "/System/Kernel/Linux/Firmware"),
    ("wifi.autoconnect", "1"),
]
db.executemany("INSERT INTO setting(key, value) VALUES (?, ?)", rows)
db.execute("PRAGMA user_version=1")
db.commit()
db.execute("VACUUM")
db.close()
PY
}

build_networking_mvp() {
  if [[ ! -x "$openssh_stage_dir/System/Networking/SSH/sbin/sshd" ]]; then
    bash "$script_dir/build_openssh_for_mixtar.sh"
  fi

  ssh_dir="$rootfs_dir/System/Networking/SSH"
  core_dir="$rootfs_dir/System/Networking/Core"
  core_runtime="$core_dir/Runtime"
  ssh_config_dir="$rootfs_dir/System/Configuration/SSH"
  net_config_dir="$rootfs_dir/System/Configuration/Networking"
  ssh_runtime_dir="$rootfs_dir/System/Runtime/Networking/SSH"
  ssh_service_root="$ssh_dir/Root"

  if [[ ! -x "$openssh_stage_dir/System/Networking/SSH/sbin/sshd" ]]; then
    printf 'ail-native-build: missing source-built OpenSSH server: %s\n' "$openssh_stage_dir/System/Networking/SSH/sbin/sshd" >&2
    exit 1
  fi

  mkdir -p "$ssh_dir" "$core_dir" "$core_runtime" "$ssh_config_dir/HostKeys" \
    "$ssh_config_dir/authorized_keys" "$net_config_dir" "$ssh_runtime_dir"

  cp -a "$openssh_stage_dir/System/Networking/SSH/." "$ssh_dir/"
  patch_elf_tree_runtime "$ssh_dir" \
    /System/Networking/SSH/Runtime/ld-linux-x86-64.so.2 \
    /System/Networking/SSH/Runtime
  rm -rf "$ssh_service_root"
  mkdir -p "$ssh_service_root/etc" "$ssh_service_root/System/Networking/SSH" \
    "$ssh_service_root/System/Configuration/SSH" "$ssh_service_root/System/Runtime/Networking/SSH" \
    "$ssh_service_root/System/Init" "$ssh_service_root/System/Logs" \
    "$ssh_service_root/System/Devices" "$ssh_service_root/System/Process" \
    "$ssh_service_root/System/Hardware" "$ssh_service_root/System/Shells" \
    "$ssh_service_root/System/Userland" "$ssh_service_root/Users" \
    "$ssh_service_root/Applications" "$ssh_service_root/Temporary" "$ssh_service_root/Volumes" \
    "$ssh_service_root/dev"
  cp -a "$ssh_dir/bin" "$ssh_dir/sbin" "$ssh_dir/libexec" "$ssh_dir/Runtime" "$ssh_service_root/System/Networking/SSH/"
  patch_elf_tree_runtime "$ssh_service_root/System/Networking/SSH" \
    /System/Networking/SSH/Runtime/ld-linux-x86-64.so.2 \
    /System/Networking/SSH/Runtime

  ip_bin="$(command -v ip || command -v /usr/sbin/ip || true)"
  if [[ -n "$ip_bin" ]]; then
    install_host_dynamic_binary "$ip_bin" "$core_dir/ip" \
      "$core_runtime" /System/Networking/Core/Runtime/ld-linux-x86-64.so.2 /System/Networking/Core/Runtime || true
    wrap_runtime_binary "$core_dir/ip" /System/Networking/Core/Runtime || true
  fi
  for core_tool in mount umount dmesg; do
    core_tool_bin="$(command -v "$core_tool" || command -v "/usr/bin/$core_tool" || command -v "/usr/sbin/$core_tool" || true)"
    if [[ -n "$core_tool_bin" ]]; then
      install_host_dynamic_binary "$core_tool_bin" "$core_dir/$core_tool" \
        "$core_runtime" /System/Networking/Core/Runtime/ld-linux-x86-64.so.2 /System/Networking/Core/Runtime || true
      wrap_runtime_binary "$core_dir/$core_tool" /System/Networking/Core/Runtime || true
    fi
  done
  if command -v dhcpcd >/dev/null 2>&1; then
    dhcpcd_bin="$(command -v dhcpcd)"
    install_host_dynamic_binary "$dhcpcd_bin" "$core_dir/dhcpcd" \
      "$core_runtime" /System/Networking/Core/Runtime/ld-linux-x86-64.so.2 /System/Networking/Core/Runtime || true
    wrap_runtime_binary "$core_dir/dhcpcd" /System/Networking/Core/Runtime || true
  fi

  cat > "$core_dir/mixtar-devices.c" <<'C'
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

static int ensure_chr(const char *path, unsigned major_no, unsigned minor_no) {
    if (mknod(path, S_IFCHR | 0666, makedev(major_no, minor_no)) != 0 && errno != EEXIST) {
        int saved = errno;
        int fd = open(path, O_WRONLY | O_CREAT, 0666);
        if (fd < 0) {
            fprintf(stderr, "mixtar-devices: mknod %s failed: %s\n", path, strerror(saved));
            fprintf(stderr, "mixtar-devices: fallback create %s failed: %s\n", path, strerror(errno));
            return -1;
        }
        close(fd);
    }
    chmod(path, 0666);
    return 0;
}

int main(void) {
    int rc = 0;
    rc |= ensure_chr("/System/Devices/null", 1, 3);
    rc |= ensure_chr("/System/Devices/zero", 1, 5);
    rc |= ensure_chr("/System/Devices/random", 1, 8);
    rc |= ensure_chr("/System/Devices/urandom", 1, 9);
    rc |= ensure_chr("/System/Devices/tty", 5, 0);
    rc |= ensure_chr("/System/Devices/console", 5, 1);
    rc |= ensure_chr("/System/Devices/ptmx", 5, 2);
    return rc == 0 ? 0 : 1;
}
C
  "$cc_bin" "${cflags[@]}" -o "$core_dir/mixtar-devices" "$core_dir/mixtar-devices.c" "${ldflags[@]}"
  rm -f "$core_dir/mixtar-devices.c"
  chmod 0755 "$core_dir/mixtar-devices"

  cat > "$ssh_config_dir/sshd_config" <<'SSHDCONFIG'
Port 22
ListenAddress 0.0.0.0
Protocol 2
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
StrictModes no
AuthorizedKeysFile /System/Configuration/SSH/authorized_keys/%u
SetEnv PATH=/System/Shells:/System/Userland
PidFile /System/Runtime/Networking/SSH/sshd.pid
HostKey /System/Configuration/SSH/HostKeys/ssh_host_ed25519_key
Subsystem sftp /System/Networking/SSH/libexec/sftp-server
UsePAM no
LogLevel DEBUG3
SSHDCONFIG

  if [[ -f "$openssh_stage_dir/System/Configuration/SSH/moduli" ]]; then
    cp "$openssh_stage_dir/System/Configuration/SSH/moduli" "$ssh_config_dir/moduli"
  fi

  : > "$ssh_config_dir/authorized_keys/$default_user"
  if [[ -n "$authorized_keys_source" ]]; then
    [[ -f "$authorized_keys_source" ]] || {
      printf 'ail-native-build: authorized keys file is missing: %s\n' "$authorized_keys_source" >&2
      exit 1
    }
    cat "$authorized_keys_source" >> "$ssh_config_dir/authorized_keys/$default_user"
  fi
  if [[ "${MIXTAR_GENERATE_TEST_SSH_KEY:-0}" = "1" ]]; then
    test_key="$out_dir/mixtar-ssh-test-key"
    if [[ ! -f "$test_key" ]]; then
      ssh-keygen -q -t ed25519 -N '' -f "$test_key" -C "mixtarrvs-generated-access"
    fi
    cat "$test_key.pub" >> "$ssh_config_dir/authorized_keys/$default_user"
  fi
  chmod 0600 "$ssh_config_dir/authorized_keys/$default_user"

  host_key="$out_dir/mixtar-ssh-host-ed25519-key"
  if [[ ! -f "$host_key" ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "$host_key" -C "mixtarrvs-host-key"
  fi
  cp "$host_key" "$ssh_config_dir/HostKeys/ssh_host_ed25519_key"
  cp "$host_key.pub" "$ssh_config_dir/HostKeys/ssh_host_ed25519_key.pub"
  chmod 0600 "$ssh_config_dir/HostKeys/ssh_host_ed25519_key"
  chmod 0644 "$ssh_config_dir/HostKeys/ssh_host_ed25519_key.pub"

  cat > "$ssh_service_root/etc/passwd" <<EOF
root:x:0:0:root:/Users/$admin_user:/System/Shells/zsh.apx/Program/zsh
sshd:x:22:22:sshd:/System/Runtime/Networking/SSH/empty:/System/Userland/false
$default_user:x:1000:1000:$default_user:/Users/$default_user:/System/Shells/zsh.apx/Program/zsh
EOF
  cat > "$ssh_service_root/etc/group" <<EOF
root:x:0:
sshd:x:22:
$default_user:x:1000:
EOF
  cat > "$ssh_service_root/etc/shadow" <<EOF
root:!:1:0:99999:7:::
$default_user:x:1:0:99999:7:::
EOF
  cat > "$ssh_service_root/etc/nsswitch.conf" <<'EOF'
passwd: files
group: files
shadow: files
hosts: files dns
EOF
  chmod 0644 "$ssh_service_root/etc/passwd" "$ssh_service_root/etc/group" "$ssh_service_root/etc/nsswitch.conf"
  chmod 0600 "$ssh_service_root/etc/shadow"

  build_wifi_mvp

  cat > "$ssh_dir/mixtar-sshd-service.c" <<'C'
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

static int mkdir_one(const char *path, mode_t mode) {
    if (mkdir(path, mode) == 0 || errno == EEXIST) {
        return 0;
    }
    return -1;
}

static int bind_dir(const char *source, const char *target) {
    mkdir_one(target, 0755);
    if (mount(source, target, 0, MS_BIND | MS_REC, 0) == 0 || errno == EBUSY) {
        return 0;
    }
    fprintf(stderr, "mixtar-sshd-service: bind %s -> %s failed: %s\n", source, target, strerror(errno));
    return -1;
}

static void ensure_runtime_file(const char *path) {
    int fd = open(path, O_WRONLY | O_CREAT, 0666);
    if (fd >= 0) {
        close(fd);
        chmod(path, 0666);
    }
}

static void attach_log(void) {
    int fd;
    mkdir_one("/System/Runtime/Networking/SSH", 0755);
    fd = open("/System/Runtime/Networking/SSH/sshd-service.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        dup2(fd, 1);
        dup2(fd, 2);
        if (fd > 2) {
            close(fd);
        }
    }
}

int main(void) {
    const char *root = "/System/Networking/SSH/Root";
    attach_log();
    fprintf(stderr, "mixtar-sshd-service: preparing root\n");
    bind_dir("/System/Configuration", "/System/Networking/SSH/Root/System/Configuration");
    bind_dir("/System/Runtime", "/System/Networking/SSH/Root/System/Runtime");
    bind_dir("/System/Init", "/System/Networking/SSH/Root/System/Init");
    bind_dir("/System/Logs", "/System/Networking/SSH/Root/System/Logs");
    bind_dir("/System/Devices", "/System/Networking/SSH/Root/System/Devices");
    bind_dir("/System/Devices", "/System/Networking/SSH/Root/dev");
    bind_dir("/System/Process", "/System/Networking/SSH/Root/System/Process");
    bind_dir("/System/Hardware", "/System/Networking/SSH/Root/System/Hardware");
    bind_dir("/System/Shells", "/System/Networking/SSH/Root/System/Shells");
    bind_dir("/System/Userland", "/System/Networking/SSH/Root/System/Userland");
    bind_dir("/Users", "/System/Networking/SSH/Root/Users");
    bind_dir("/Applications", "/System/Networking/SSH/Root/Applications");
    bind_dir("/Temporary", "/System/Networking/SSH/Root/Temporary");
    bind_dir("/Volumes", "/System/Networking/SSH/Root/Volumes");

    if (chroot(root) != 0) {
        fprintf(stderr, "mixtar-sshd-service: chroot failed: %s\n", strerror(errno));
        return 111;
    }
    if (chdir("/") != 0) {
        fprintf(stderr, "mixtar-sshd-service: chdir failed: %s\n", strerror(errno));
        return 111;
    }
    mkdir_one("/System", 0755);
    mkdir_one("/System/Devices", 0755);
    mkdir_one("/dev", 0755);
    mkdir_one("/run", 0755);
    mkdir_one("/run/sshd", 0755);
    mkdir_one("/var", 0755);
    mkdir_one("/var/empty", 0755);
    mkdir_one("/System/Runtime/Networking/SSH/empty", 0755);
    ensure_runtime_file("/System/Devices/null");
    ensure_runtime_file("/System/Devices/zero");
    ensure_runtime_file("/System/Devices/random");
    ensure_runtime_file("/System/Devices/urandom");
    setenv("LD_LIBRARY_PATH", "/System/Networking/SSH/Runtime", 1);
    setenv("PATH", "/System/Networking/SSH/bin:/System/Networking/SSH/sbin:/System/Userland", 1);
    char *argv[] = {
        "/System/Networking/SSH/sbin/sshd",
        "-D",
        "-e",
        "-f",
        "/System/Configuration/SSH/sshd_config",
        "-h",
        "/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key",
        0,
    };
    fprintf(stderr, "mixtar-sshd-service: exec sshd\n");
    execv(argv[0], argv);
    fprintf(stderr, "mixtar-sshd-service: exec failed: %s\n", strerror(errno));
    return 127;
}
C
  "$cc_bin" "${cflags[@]}" -o "$ssh_dir/mixtar-sshd-service" "$ssh_dir/mixtar-sshd-service.c" "${ldflags[@]}"
  rm -f "$ssh_dir/mixtar-sshd-service.c"
  chmod 0755 "$ssh_dir/mixtar-sshd-service"

  python3 - "$rootfs_dir" "$default_user" <<'PY'
import pathlib
import sqlite3
import sys

root = pathlib.Path(sys.argv[1])
default_user = sys.argv[2]

def write_config(relpath, rows):
    path = root / relpath
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript(
        """
        PRAGMA page_size=1024;
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        CREATE TABLE setting(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """
    )
    db.executemany("INSERT INTO setting(key, value) VALUES (?, ?)", rows)
    db.execute("PRAGMA user_version=1")
    db.commit()
    db.execute("VACUUM")
    db.close()

write_config(
    "System/Configuration/Networking/Networking.config",
    [
        ("network.backend", "linux-kernel"),
        ("network.stack", "kernel-native"),
        ("dhcp.default", "1"),
        ("qemu.eth0.static", "10.0.2.15/24"),
        ("qemu.eth0.gateway", "10.0.2.2"),
        ("wifi.enabled", "1"),
        ("wifi.service", "/System/Networking/WiFi/mixtar-wifi-service"),
        ("wifi.wlan0.address_mode", "dhcp"),
        ("bsd.network.stack.ported", "0"),
        ("service.ssh.enabled", "1"),
        ("service.ssh.start", "/System/Networking/start-networking"),
        ("service.ssh.root", "/System/Networking/SSH/Root"),
        ("user.default", default_user),
    ],
)
write_config(
    "System/Configuration/SSH/SSH.config",
    [
        ("sshd.path", "/System/Networking/SSH/sbin/sshd"),
        ("sshd.launcher", "/System/Networking/SSH/mixtar-sshd-service"),
        ("sshd.config", "/System/Configuration/SSH/sshd_config"),
        ("sshd.runtime", "/System/Runtime/Networking/SSH"),
        ("authorized_keys.dir", "/System/Configuration/SSH/authorized_keys"),
        ("hostkey.ed25519", "/System/Configuration/SSH/HostKeys/ssh_host_ed25519_key"),
        ("port", "22"),
        ("password_authentication", "0"),
        ("pubkey_authentication", "1"),
    ],
)
PY

cat > "$rootfs_dir/System/Networking/start-networking" <<'ZSH'
#!/System/Shells/zsh.apx/Program/zsh
setopt null_glob

PATH=/System/Networking/Core:/System/Userland:/System/Shells/zsh.apx/Program:$PATH
export PATH
LD_LIBRARY_PATH=/System/Networking/Core/Runtime:/System/Shells/zsh.apx/Runtime:${LD_LIBRARY_PATH:-}
export LD_LIBRARY_PATH

mkdir -p /System/Runtime/Networking
mkdir -p /System/Runtime/Networking/WiFi

mi_fix_ssh_permissions() {
  chmod 0755 /System/Configuration/SSH 2>/System/Devices/null || true
  chmod 0700 /System/Configuration/SSH/HostKeys 2>/System/Devices/null || true
  chmod 0600 /System/Configuration/SSH/HostKeys/ssh_host_*_key 2>/System/Devices/null || true
  chmod 0644 /System/Configuration/SSH/HostKeys/ssh_host_*_key.pub 2>/System/Devices/null || true
  chmod 0644 /System/Configuration/SSH/sshd_config /System/Configuration/SSH/SSH.config /System/Configuration/SSH/moduli 2>/System/Devices/null || true
  chmod 0755 /System/Configuration/SSH/authorized_keys 2>/System/Devices/null || true
  chmod 0644 /System/Configuration/SSH/authorized_keys/* 2>/System/Devices/null || true
}

mi_log() {
  print -r -- "$1" >>/System/Runtime/Networking/networking.log
  print -r -- "$1" >>/System/Logs/networking.log
}

mi_ip() {
  /System/Networking/Core/ip "$@" >>/System/Runtime/Networking/networking.log 2>&1
}

mi_cmdline_has() {
  local needle="$1"
  local cmdline
  if [[ -f /System/Process/cmdline ]]; then
    cmdline="$(/System/Userland/cat /System/Process/cmdline 2>/System/Devices/null || true)"
    [[ "$cmdline" == *"$needle"* ]]
    return $?
  fi
  return 1
}

mi_mount_esp() {
  mkdir -p /Volumes/ESP
  if [[ -f /System/Process/mounts ]] && grep -q ' /Volumes/ESP ' /System/Process/mounts; then
    return 0
  fi
  if [[ -x /System/Networking/Core/mount && -e /System/Devices/nvme0n1p1 ]]; then
    /System/Networking/Core/mount -t vfat /System/Devices/nvme0n1p1 /Volumes/ESP >>/System/Runtime/Networking/persist.log 2>&1
    return $?
  fi
  return 1
}

mi_persist_network_diag() {
  local tag="$1"
  if ! mi_mount_esp; then
    mi_log "networking: persist skipped, ESP unavailable"
    return 0
  fi

  local dir="/Volumes/ESP/EFI/mixtarrvs-rt/logs/networking-$tag"
  mkdir -p "$dir"
  {
    print -r -- "tag=$tag"
    print -r -- "cmdline:"
    /System/Userland/cat /System/Process/cmdline 2>/System/Devices/null || true
    print -r -- ""
    print -r -- "net-class:"
    print -rl -- /System/Hardware/class/net/* 2>/System/Devices/null || true
    print -r -- "ip-addr:"
    /System/Networking/Core/ip -br addr 2>&1 || true
    print -r -- "ip-route:"
    /System/Networking/Core/ip route 2>&1 || true
    print -r -- "wireless:"
    /System/Userland/cat /System/Process/net/wireless 2>/System/Devices/null || true
    print -r -- "modules:"
    /System/Userland/cat /System/Process/modules 2>/System/Devices/null | grep -E 'iwl|cfg80211|mac80211|e1000e|rfkill' || true
  } >"$dir/state.txt"

  cp /System/Runtime/Networking/*.log "$dir/" 2>/System/Devices/null || true
  mkdir -p "$dir/SSH"
  cp /System/Runtime/Networking/SSH/*.log "$dir/SSH/" 2>/System/Devices/null || true
  cp /System/Runtime/Networking/WiFi/*.log "$dir/" 2>/System/Devices/null || true
  if [[ -x /System/Networking/Core/dmesg ]]; then
    /System/Networking/Core/dmesg >"$dir/dmesg.txt" 2>&1 || true
  fi
  sync
}

mi_diag_autoreturn_loop() {
  local attempt
  for attempt in {1..60}; do
    mi_persist_network_diag "attempt-$attempt"
    sleep 5
  done
  mi_persist_network_diag "final"
}

mi_configure_static() {
  local iface="$1"
  local cidr="$2"
  local gateway="$3"
  local ipaddr="${cidr%%/*}"

  if [[ ! -d "/System/Hardware/class/net/$iface" ]]; then
    return 1
  fi

  mi_log "networking: configure $iface $cidr"
  mi_ip link set "$iface" up || true

  local current
  current="$(/System/Networking/Core/ip -4 addr show dev "$iface" 2>&1)"
  if [[ "$current" != *"$ipaddr"* ]]; then
    mi_ip addr add "$cidr" dev "$iface" || true
  fi

  if [[ -n "$gateway" ]]; then
    local routes
    routes="$(/System/Networking/Core/ip route 2>&1)"
    if [[ "$routes" != *"default via $gateway dev $iface"* ]]; then
      mi_ip route add default via "$gateway" dev "$iface" || true
    fi
  fi

  /System/Networking/Core/ip -br addr >>/System/Runtime/Networking/networking.log 2>&1 || true
  /System/Networking/Core/ip route >>/System/Runtime/Networking/networking.log 2>&1 || true
  return 0
}

mi_network_ready() {
  /System/Networking/Core/ip -4 -o addr show scope global 2>/System/Devices/null | grep -q . || return 1
  /System/Networking/Core/ip route show default 2>/System/Devices/null | grep -q '^default ' || return 1
  return 0
}

mi_network_config_loop() {
  local attempt
  for attempt in {1..90}; do
    if [[ -d /System/Hardware/class/net/lo ]]; then
      mi_ip link set lo up || true
    fi

    if mi_network_ready; then
      echo "network ready after ${attempt}s"
      /System/Networking/Core/ip -br addr || true
      /System/Networking/Core/ip route || true
      return 0
    fi

    if [[ -d /System/Hardware/class/net/eth0 ]]; then
      mi_configure_static eth0 10.0.2.15/24 10.0.2.2 || true
    fi

    if [[ -d /System/Hardware/class/net/wlan0 ]]; then
      if (( attempt == 1 || attempt % 10 == 0 )); then
        echo "waiting for iwd DHCP on wlan0 attempt=$attempt"
      fi
    elif (( attempt == 1 || attempt % 10 == 0 )); then
      echo "waiting for a physical network interface attempt=$attempt"
    fi

    sleep 1
  done
  echo "network configuration timed out without an address and default route"
  return 1
}

mi_load_kernel_modules() {
  local modprobe=/System/Kernel/Linux/Tools/modprobe
  if [[ ! -x "$modprobe" ]]; then
    mi_log "networking: modprobe unavailable"
    return 0
  fi

  local modules_base=/System/Kernel/Linux/lib/modules
  local version
  for version in "$modules_base"/*; do
    [[ -d "$version" ]] || continue
    version="${version:t}"
    mi_log "networking: loading kernel modules version=$version"
    "$modprobe" -d /System/Kernel/Linux -S "$version" -a \
      af_alg algif_hash algif_skcipher algif_aead algif_rng crypto_user \
      ecb md5 crc32c sha256_generic aesni_intel des_generic cmac hmac sha512_generic sha1_generic \
      vfat fat nls_cp437 nls_iso8859_1 \
      cfg80211 mac80211 iwlwifi \
      iwlmvm e1000e >>/System/Runtime/Networking/modules.log 2>&1 || true
  done
}

mi_log "networking: starting service"
mi_fix_ssh_permissions
if mi_cmdline_has 'mixtar.persist_logs=1' || mi_cmdline_has 'mixtar.autoreturn=1'; then
  mi_diag_autoreturn_loop </System/Devices/null >/System/Runtime/Networking/persist-loop.log 2>&1 &
fi
mi_load_kernel_modules

if [[ -x /System/Networking/WiFi/mixtar-wifi-service ]]; then
  mi_log "networking: starting WiFi service"
  /System/Networking/WiFi/mixtar-wifi-service >/System/Logs/networking-wifi.log 2>&1 || true
fi

mi_network_config_loop </System/Devices/null >/System/Logs/network-config-loop.log 2>&1 &

sleep 2
while true; do
  mi_log "networking: exec sshd"
  /System/Networking/SSH/mixtar-sshd-service >>/System/Logs/sshd-wrapper.log 2>&1
  rc=$?
  mi_log "networking: sshd exited rc=$rc"
  sleep 5
done
ZSH
  chmod 0755 "$rootfs_dir/System/Networking/start-networking"

  if command -v strip >/dev/null 2>&1; then
    strip "$ssh_dir"/bin/* "$ssh_dir"/sbin/* "$ssh_dir"/libexec/* "$ssh_dir"/mixtar-sshd-service "$core_dir"/ip "$core_dir"/dhcpcd 2>/dev/null || true
  fi
}

case "$rootfs_dir" in
  "$out_dir"/ail-native-initramfs-root) ;;
  *)
    printf 'ail-native-build: refusing unsafe rootfs_dir: %s\n' "$rootfs_dir" >&2
    exit 1
    ;;
esac
rm -rf "$rootfs_dir"

mkdir -p "$rootfs_dir/System/Configuration" "$rootfs_dir/System/Init"

reuse_pid1_bin="${MIXTAR_REUSE_PID1_BIN:-}"
if [[ -n "$reuse_pid1_bin" ]]; then
  reuse_pid1_bin="$(readlink -f "$reuse_pid1_bin")"
  case "$reuse_pid1_bin" in
    "$out_dir"/*) ;;
    *)
      printf 'ail-native-build: refusing PID1 reuse outside Generated: %s\n' "$reuse_pid1_bin" >&2
      exit 1
      ;;
  esac
  if [[ ! -f "$reuse_pid1_bin" || ! -x "$reuse_pid1_bin" ]]; then
    printf 'ail-native-build: reusable PID1 is not executable: %s\n' "$reuse_pid1_bin" >&2
    exit 1
  fi
  install -m 0755 "$reuse_pid1_bin" "$rootfs_dir/System/Init/MixtarRVS"
  printf 'ail-native-build: reused validated PID1: %s\n' "$reuse_pid1_bin"
else
  python3 "$ailang_root/ailang.py" "$ail_init_src" --check
  python3 "$ailang_root/ailang.py" "$ail_init_src" --effect-policy
  python3 "$ailang_root/ailang.py" "$ail_init_verify_src" --check
  python3 "$ailang_root/ailang.py" "$ail_init_verify_src" --backend=c -o "$verifier_bin"
  "$verifier_bin" "$ail_init_src"
  prepare_pid1_sqlite
  python3 "$ailang_root/ailang.py" "$ail_init_src" --emit-c -o "$generated_c"
  pid1_temp_c="${TMPDIR:-/tmp}/mixtar-init.$$.c"
  pid1_temp_o="${TMPDIR:-/tmp}/mixtar-sqlite-pid1.$$.o"
  pid1_temp_bin="${TMPDIR:-/tmp}/MixtarRVS-init.$$.bin"
  cp "$generated_c" "$pid1_temp_c"
  cp "$sqlite_pid1_o" "$pid1_temp_o"
  if ! "$cc_bin" "${cflags[@]}" -o "$pid1_temp_bin" "$pid1_temp_c" "$pid1_temp_o" "${ldflags[@]}"; then
    rm -f -- "$pid1_temp_c" "$pid1_temp_o" "$pid1_temp_bin"
    exit 1
  fi
  install -m 0755 "$pid1_temp_bin" "$rootfs_dir/System/Init/MixtarRVS"
  rm -f -- "$pid1_temp_c" "$pid1_temp_o" "$pid1_temp_bin"
fi
chmod 0755 "$rootfs_dir/System/Init/MixtarRVS"
if command -v strip >/dev/null 2>&1; then
  strip "$rootfs_dir/System/Init/MixtarRVS" 2>/dev/null || true
fi

reuse_boot_bin="${MIXTAR_REUSE_BOOT_BIN:-}"
if [[ -n "$reuse_boot_bin" ]]; then
  reuse_boot_bin="$(readlink -f "$reuse_boot_bin")"
  case "$reuse_boot_bin" in
    "$out_dir"/*) ;;
    *)
      printf 'ail-native-build: refusing MixtarBoot reuse outside Generated: %s\n' "$reuse_boot_bin" >&2
      exit 1
      ;;
  esac
  if [[ ! -f "$reuse_boot_bin" || ! -x "$reuse_boot_bin" ]]; then
    printf 'ail-native-build: reusable MixtarBoot is not executable: %s\n' "$reuse_boot_bin" >&2
    exit 1
  fi
  install -m 0755 "$reuse_boot_bin" "$rootfs_dir/System/Init/MixtarBoot"
  printf 'ail-native-build: reused validated MixtarBoot: %s\n' "$reuse_boot_bin"
else
  python3 "$ailang_root/ailang.py" "$ail_boot_src" --check
  python3 "$ailang_root/ailang.py" "$ail_boot_src" --effect-policy
  python3 "$ailang_root/ailang.py" "$ail_boot_src" --emit-c -o "$generated_boot_c"
  boot_temp_c="${TMPDIR:-/tmp}/mixtar-boot.$$.c"
  boot_temp_bin="${TMPDIR:-/tmp}/MixtarBoot.$$.bin"
  cp "$generated_boot_c" "$boot_temp_c"
  if ! "$cc_bin" "${cflags[@]}" -o "$boot_temp_bin" "$boot_temp_c" "${ldflags[@]}"; then
    rm -f -- "$boot_temp_c" "$boot_temp_bin"
    exit 1
  fi
  install -m 0755 "$boot_temp_bin" "$rootfs_dir/System/Init/MixtarBoot"
  rm -f -- "$boot_temp_c" "$boot_temp_bin"
fi
if command -v strip >/dev/null 2>&1; then
  strip "$rootfs_dir/System/Init/MixtarBoot" 2>/dev/null || true
fi
[ -x "$rootfs_dir/System/Init/MixtarBoot" ] || {
  printf 'ail-native-build: missing MixtarBoot handoff\n' >&2
  exit 1
}
build_boot_initramfs

if [[ ! -f "$console_setup_src" ]]; then
  printf 'ail-native-build: missing ConsoleSetup source: %s\n' "$console_setup_src" >&2
  exit 1
fi
console_setup_temp="${TMPDIR:-/tmp}/MixtarRVS-ConsoleSetup.$$.bin"
if ! "$cc_bin" -O2 -static -Wall -Wextra -Werror \
    -o "$console_setup_temp" "$console_setup_src"; then
  rm -f -- "$console_setup_temp"
  exit 1
fi
install -m 0755 "$console_setup_temp" "$rootfs_dir/System/Init/ConsoleSetup"
rm -f -- "$console_setup_temp"

python3 - "$rootfs_dir" "$system_name" "$default_user" "$admin_user" <<'PY'
import os
import pathlib
import sqlite3
import sys

root = pathlib.Path(sys.argv[1])
system_name = sys.argv[2]
default_user = sys.argv[3]
admin_user = sys.argv[4]

root_dirs = [
    "/Applications",
    "/System",
    "/Temporary",
    "/Users",
    "/Volumes",
    "/System/Configuration",
    "/System/Configuration/Settings",
    "/System/Devices",
    "/System/Devices/pts",
    "/System/EFI",
    "/System/EFI/MixtarRVS",
    "/System/Hardware",
    "/System/Init",
    "/System/Kernel",
    "/System/Kernel/Linux",
    "/System/Kernel/Linux/Firmware",
    "/System/Kernel/Linux/RT",
    "/System/Logs",
    "/System/Networking",
    "/System/Networking/Core",
    "/System/Networking/SSH",
    "/System/Networking/WiFi",
    "/System/Process",
    "/System/Resources",
    "/System/Runtime",
    "/System/Runtime/Networking",
    "/System/Runtime/Networking/SSH",
    "/System/Runtime/Networking/WiFi",
    "/System/Runtime/run",
    "/System/Shells",
    "/System/Userland",
    "/System/Compatibility",
    "/System/Compatibility/POSIX",
    "/System/Compatibility/POSIX/OpenBSD",
    "/System/Compatibility/POSIX/FreeBSD",
    "/System/Compatibility/POSIX/Linux",
]
users = [
    (default_user, f"/Users/{default_user}", "/System/Shells/zsh.apx/Program/zsh", 1000, 1000),
]
if admin_user != default_user:
    users.append(
        (admin_user, f"/Users/{admin_user}", "/System/Shells/zsh.apx/Program/zsh", 1001, 1001)
    )
chmods = [
    ("public-tmp", "/Temporary"),
    ("private-dir", f"/Users/{default_user}"),
]
if admin_user != default_user:
    chmods.append(("private-dir", f"/Users/{admin_user}"))
symlinks = [
]
mounts = [
    ("devtmpfs", "/System/Devices", "devtmpfs", 0o755),
    ("devpts", "/System/Devices/pts", "devpts", 0o755),
    ("proc", "/System/Process", "proc", 0),
    ("sysfs", "/System/Hardware", "sysfs", 0),
    ("tmpfs", "/System/Runtime/run", "tmpfs", 0o755),
    ("tmpfs", "/Temporary", "tmpfs", 0o1777),
]
personas = [
    "/System/Compatibility/POSIX/OpenBSD",
    "/System/Compatibility/POSIX/FreeBSD",
    "/System/Compatibility/POSIX/Linux",
]
meta = [
    ("system.name", system_name),
    ("default.user", default_user),
    ("default.uid", "1000"),
    ("default.gid", "1000"),
    ("users.home.root", "/Users"),
    ("users.shell.default", "/System/Shells/zsh.apx/Program/zsh"),
    ("users.uid.minimum", "1000"),
    ("users.gid.strategy", "uid"),
    ("root.path", "/"),
    ("console.path", "/System/Devices/console"),
    ("console.setup", "/System/Init/ConsoleSetup"),
    ("console.keymap", "pl"),
    ("locale.name", "C.UTF-8"),
    ("log.path", "/System/Logs/mixtar-init.log"),
    ("compat.exec", "/System/Userland/compat-exec"),
    ("compat.shell", "/System/Userland/sh"),
    ("session.exec", "/System/Shells/zsh.apx/Program/zsh"),
    ("session.reboot.status", "200"),
    ("session.poweroff.status", "201"),
    ("lifecycle.reboot.command", "/System/Userland/reboot"),
    ("lifecycle.poweroff.command", "/System/Userland/poweroff"),
    ("lifecycle.control.path", "/System/Runtime/Lifecycle"),
    ("networking.service", "/System/Networking/start-networking"),
    ("networking.ping.group_range.path", "/System/Process/sys/net/ipv4/ping_group_range"),
    ("networking.ping.gid.min", "0"),
    ("networking.ping.gid.max", "1000"),
    ("compat openbsd sh", "openbsd"),
    ("compat freebsd sh", "freebsd"),
    ("compat linux sh", "linux"),
]

for path in root_dirs:
    (root / path.lstrip("/")).mkdir(parents=True, exist_ok=True)
for _, home, _, _, _ in users:
    (root / home.lstrip("/")).mkdir(parents=True, exist_ok=True)
for link_path, target in symlinks:
    full_link = root / link_path.lstrip("/")
    if not full_link.exists() and not full_link.is_symlink():
        os.symlink(target, full_link)

db_path = root / "System/Configuration/MixtarRVS.config"
if db_path.exists():
    db_path.unlink()
db = sqlite3.connect(db_path)
db.executescript(
    """
    PRAGMA page_size=1024;
    PRAGMA journal_mode=OFF;
    PRAGMA synchronous=OFF;
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE root_dir(path TEXT PRIMARY KEY);
    CREATE TABLE user(
        name TEXT PRIMARY KEY,
        home TEXT NOT NULL,
        shell TEXT NOT NULL,
        uid INTEGER NOT NULL UNIQUE CHECK(uid > 0),
        gid INTEGER NOT NULL CHECK(gid > 0)
    );
    CREATE TABLE chmod(mode_name TEXT NOT NULL, path TEXT NOT NULL, PRIMARY KEY(mode_name, path));
    CREATE TABLE symlink(path TEXT PRIMARY KEY, target TEXT NOT NULL);
    CREATE TABLE mount(fstype TEXT NOT NULL, target TEXT PRIMARY KEY, source TEXT NOT NULL, mode INTEGER NOT NULL);
    CREATE TABLE persona(path TEXT PRIMARY KEY);
    CREATE INDEX mount_fstype_idx ON mount(fstype);
    CREATE INDEX chmod_path_idx ON chmod(path);
    """
)
db.executemany("INSERT INTO meta(key, value) VALUES (?, ?)", meta)
db.executemany("INSERT INTO root_dir(path) VALUES (?)", [(p,) for p in root_dirs])
db.executemany("INSERT INTO user(name, home, shell, uid, gid) VALUES (?, ?, ?, ?, ?)", users)
db.executemany("INSERT INTO chmod(mode_name, path) VALUES (?, ?)", chmods)
db.executemany("INSERT INTO symlink(path, target) VALUES (?, ?)", symlinks)
db.executemany("INSERT INTO mount(fstype, target, source, mode) VALUES (?, ?, ?, ?)", mounts)
db.executemany("INSERT INTO persona(path) VALUES (?)", [(p,) for p in personas])
db.execute("PRAGMA user_version=3")
db.commit()
db.execute("VACUUM")
db.close()

init_lines = []
init_lines.extend(f"{key}={value}" for key, value in meta)
init_lines.extend(f"root.dir={path}" for path in root_dirs)
init_lines.extend(f"user={name}:{home}:{shell}" for name, home, shell, _, _ in users)
init_lines.extend(f"chmod={mode}:{path}" for mode, path in chmods)
init_lines.extend(f"symlink={path}:{target}" for path, target in symlinks)
init_lines.extend(f"mount={fstype}:{target}:{source}:{mode}" for fstype, target, source, mode in mounts)
init_lines.extend(f"persona={path}" for path in personas)
(root / "System/Configuration/MixtarRVS.init").write_text("\n".join(init_lines) + "\n", encoding="utf-8")
(root / "System/Configuration/mixtar-release").write_text(
    "\n".join(
        [
            f"NAME={system_name}",
            "STAGE=ail-native-init-proof",
            "INIT=AILang",
            "ROOT_MODEL=native-mixtar",
            "CASE_SENSITIVE=1",
            "POSIX=compatibility-only",
        ]
    )
    + "\n",
    encoding="utf-8",
)
(root / "System/Configuration/hostname").write_text(system_name + "\n", encoding="utf-8")
PY

build_init_tools
build_zsh_terminal
build_networking_mvp

(
  cd "$rootfs_dir"
  find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9
) > "$image"

printf 'ail-native-build: wrote %s\n' "$image"
printf 'ail-native-build: wrote %s\n' "$boot_image"
printf 'ail-native-build: root %s\n' "$rootfs_dir"
file "$rootfs_dir/System/Init/MixtarRVS"
ldd "$rootfs_dir/System/Init/MixtarRVS" 2>&1 || true
