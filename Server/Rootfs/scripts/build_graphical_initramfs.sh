#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

base_image="$repo_root/Server/Rootfs/Generated/mixtar-initramfs.cpio.gz"
rootfs_dir="$repo_root/Server/Rootfs/Generated/initramfs-root"
out_dir="$repo_root/Server/Rootfs/Generated"
image="$out_dir/mixtar-graphical-initramfs.cpio.gz"
desktop_profile="${MIXTAR_DESKTOP_PROFILE:-base}"
mddm_auth_test_mode="${MIXTAR_MDDM_AUTH_TEST_MODE:-ON}"

bash "$script_dir/build_initramfs.sh"

mkdir -p "$rootfs_dir/System/Runtime/Desktop"

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

copy_tree_runtime_deps() {
  local tree="$1"
  find "$tree" -type f -name '*.so*' -print0 |
      while IFS= read -r -d '' binary; do
        copy_runtime_deps "$binary"
      done
}

copy_shared_library_by_name() {
  local name="$1"
  local lib

  lib="$(ldconfig -p 2>/dev/null |
      awk -v name="$name" '$1 == name { print $NF; exit }')"
  if [[ -n "$lib" && -e "$lib" ]]; then
    copy_runtime_file "$lib"
    copy_runtime_deps "$lib"
    return 0
  fi
  return 1
}

copy_pam_module() {
  local name="$1"
  local module

  module="$(find /usr/lib /lib -path "*/security/$name" -type f 2>/dev/null |
      head -n 1)"
  if [[ -z "$module" ]]; then
    echo "graphical-rootfs: warning: missing PAM module $name" >&2
    return 1
  fi
  copy_runtime_file "$module"
  copy_runtime_deps "$module"
}

copy_pam_runtime() {
  if ! copy_shared_library_by_name libpam.so.0; then
    echo "graphical-rootfs: warning: missing libpam.so.0" >&2
  fi

  for module in \
      pam_nologin.so \
      pam_faildelay.so \
      pam_unix.so \
      pam_limits.so \
      pam_umask.so \
      pam_env.so; do
    copy_pam_module "$module" || true
  done
}

copy_desktop_binary() {
  local name="$1"
  local src="$2"

  if [[ ! -x "$src" ]]; then
    echo "graphical-rootfs: missing $name at $src" >&2
    exit 1
  fi

  cp "$src" "$rootfs_dir/System/Runtime/Desktop/$name"
  chmod 0755 "$rootfs_dir/System/Runtime/Desktop/$name"
  copy_runtime_deps "$src"
}

build_ailang_ui_smoke() {
  local src="$repo_root/../AILang-Pure/examples/ui/ui_backend_smoke.ail"
  local compiler="$repo_root/../AILang-Pure/ailang.py"
  local out="$out_dir/ailang-ui-smoke"

  if [[ -f "$compiler" && -f "$src" ]]; then
    python3 "$compiler" "$src" \
      --backend=c \
      --native-toolchain=gcc \
      -o "$out"
  elif [[ -x "$out" ]]; then
    echo "graphical-rootfs: using pre-built AILang UI smoke" >&2
  else
    echo "graphical-rootfs: skipping optional AILang UI smoke" >&2
    return 0
  fi

  copy_desktop_binary ailang-ui-smoke "$out"
}

build_mixtar_auth_helper() {
  local src="$repo_root/Server/Auth/mixtar_auth.ail"
  local pam_src="$repo_root/Server/Auth/mixtar_auth_pam.c"
  local generated_src="$repo_root/Server/Auth/Generated/mixtar_auth.c"
  local compiler="$repo_root/../AILang-Pure/ailang.py"
  local main_c="$out_dir/mixtar_auth_main.c"
  local pam_obj="$out_dir/mixtar_auth_pam.o"
  local out="$out_dir/mixtar-auth"

  if [[ ! -f "$pam_src" ]]; then
    echo "graphical-rootfs: missing PAM auth helper source" >&2
    return 1
  fi

  if [[ -f "$compiler" && -f "$src" ]]; then
    python3 "$compiler" "$src" --emit-c -o "$main_c"
  elif [[ -f "$generated_src" ]]; then
    echo "graphical-rootfs: using pre-generated auth helper C" >&2
    cp "$generated_src" "$main_c"
  else
    echo "graphical-rootfs: missing auth helper source and generated fallback" >&2
    return 1
  fi

  cc -std=c23 -O3 -Wall -Wextra -Werror -c "$pam_src" -o "$pam_obj"
  cc -O3 "$main_c" "$pam_obj" -ldl -o "$out"
  mkdir -p "$rootfs_dir/System/Tools"
  cp "$out" "$rootfs_dir/System/Tools/mixtar-auth"
  chmod 0755 "$rootfs_dir/System/Tools/mixtar-auth"
  copy_runtime_deps "$out"
  copy_pam_runtime
}

build_xwayland_wrapper() {
  local wrapper_src="$out_dir/xwayland_smoke_wrapper.c"
  local wrapper_bin="$rootfs_dir/System/Runtime/Desktop/Xwayland"
  local real_bin="$rootfs_dir/System/Runtime/Desktop/Xwayland.real"

  mv "$wrapper_bin" "$real_bin"
  cat > "$wrapper_src" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int has_auth_arg(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-auth") == 0) {
            return 1;
        }
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *real = "/System/Runtime/Desktop/Xwayland.real";
    const char *auth = getenv("XAUTHORITY");
    int add_auth = auth != NULL && auth[0] != '\0' && !has_auth_arg(argc, argv);
    size_t next_count = (size_t)argc + (add_auth ? 2U : 0U) + 1U;
    char **next = calloc(next_count, sizeof(char *));
    if (next == NULL) {
        perror("Xwayland wrapper");
        return 127;
    }

    int out = 0;
    next[out++] = (char *)real;
    if (add_auth) {
        next[out++] = "-auth";
        next[out++] = (char *)auth;
    }
    for (int i = 1; i < argc; i++) {
        next[out++] = argv[i];
    }
    next[out] = NULL;

    execv(real, next);
    perror(real);
    return 127;
}
EOF

  cc -O2 -Wall -Wextra -Werror -o "$wrapper_bin" "$wrapper_src"
  chmod 0755 "$wrapper_bin" "$real_bin"
  copy_runtime_deps "$wrapper_bin"
}

copy_resource_tree() {
  local src="$1"
  local dst="$2"

  if [[ -d "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst"
    cp -a "$src" "$dst"
  else
    echo "graphical-rootfs: warning: missing resource $src" >&2
  fi
}

copy_optional_resource_tree() {
  local src="$1"
  local dst="$2"

  if [[ -d "$src" ]]; then
    copy_resource_tree "$src" "$dst"
  fi
}

copy_desktop_binary labwc /usr/bin/labwc
copy_desktop_binary Xwayland /usr/bin/Xwayland
copy_desktop_binary xdpyinfo /usr/bin/xdpyinfo
copy_desktop_binary xkbcomp /usr/bin/xkbcomp
copy_desktop_binary xauth /usr/bin/xauth
copy_desktop_binary xterm /usr/bin/xterm

if [[ "$desktop_profile" == "rich" ]]; then
  mddm_repo="${MDDM_REPO:-$repo_root/../FreeBSD-Mixtar-Theme/Development/MDDM}"
  mddm_auth_label="test"
  if [[ "$mddm_auth_test_mode" == "OFF" || "$mddm_auth_test_mode" == "0" ]]; then
    mddm_auth_label="pam"
  fi
  mddm_build="${MDDM_BUILD_DIR:-$mddm_repo/build-codex-mddm-rootfs-$mddm_auth_label}"
  if [[ ! -x "$mddm_build/mddm/mddm" ]]; then
    cmake -S "$mddm_repo" -B "$mddm_build" \
      -DBUILD_TESTING=ON \
      -DMDDM_AUTH_TEST_MODE="$mddm_auth_test_mode" \
      -DCMAKE_BUILD_TYPE=Release >/dev/null
  fi
  cmake --build "$mddm_build" --target mddm mixtar-shell -j2

  copy_desktop_binary dbus-daemon /usr/bin/dbus-daemon
  copy_desktop_binary mddm "$mddm_build/mddm/mddm"
  copy_desktop_binary mixtar-shell "$mddm_build/shell/mixtar-shell"
  mkdir -p "$rootfs_dir/System/Config/pam.d"
  cp "$repo_root/Server/Auth/pam.d/mixtar-login" \
    "$rootfs_dir/System/Config/pam.d/mixtar-login"
  chmod 0644 "$rootfs_dir/System/Config/pam.d/mixtar-login"
  build_mixtar_auth_helper
  cp "$mddm_repo/mddm/qml"/*.qml "$rootfs_dir/System/Runtime/Desktop/"
  cp "$mddm_repo/mddm/qml"/*.js "$rootfs_dir/System/Runtime/Desktop/"
  cp "$mddm_repo/shell/qml"/*.qml "$rootfs_dir/System/Runtime/Desktop/"
  cp "$mddm_repo/shell/qml"/*.js "$rootfs_dir/System/Runtime/Desktop/"
  if [[ -d "$mddm_repo/shell/assets" ]]; then
    mkdir -p "$rootfs_dir/System/Runtime/Desktop/assets"
    cp -a "$mddm_repo/shell/assets/." \
      "$rootfs_dir/System/Runtime/Desktop/assets/"
  fi
  cp "$mddm_repo/shell/etc/context-menus.conf" "$rootfs_dir/System/Runtime/Desktop/context-menus.conf"
  cp "$mddm_build/mddm/mddm.conf" "$rootfs_dir/System/Runtime/Desktop/mddm.conf"
  cp "$mddm_build/mddm/shortcuts.conf" "$rootfs_dir/System/Runtime/Desktop/shortcuts.conf"
  cat > "$rootfs_dir/System/Runtime/Desktop/qt.conf" <<'EOF'
[Paths]
Plugins = /System/Resources/qt6/plugins
Qml2Imports = /System/Resources/qt6/qml
EOF

  copy_resource_tree /usr/share/dbus-1 "$rootfs_dir/System/Resources/dbus-1"
  copy_resource_tree /usr/lib/x86_64-linux-gnu/qt6/plugins \
    "$rootfs_dir/System/Resources/qt6/plugins"
  copy_resource_tree /usr/lib/x86_64-linux-gnu/qt6/qml \
    "$rootfs_dir/System/Resources/qt6/qml"
  copy_tree_runtime_deps "$rootfs_dir/System/Resources/qt6"
  copy_optional_resource_tree /etc/dbus-1 "$rootfs_dir/System/Config/dbus-1"
  mkdir -p "$rootfs_dir/System/Config" "$rootfs_dir/var/lib/dbus"
  printf '9d0f1a2b3c4d5e6f8091a2b3c4d5e6f7\n' \
    > "$rootfs_dir/System/Config/machine-id"
  printf '9d0f1a2b3c4d5e6f8091a2b3c4d5e6f7\n' \
    > "$rootfs_dir/var/lib/dbus/machine-id"
elif [[ "$desktop_profile" != "base" ]]; then
  echo "graphical-rootfs: unknown MIXTAR_DESKTOP_PROFILE=$desktop_profile" >&2
  exit 1
fi

panel_src="$repo_root/../FreeBSD-Mixtar-Theme/MixtarRVS/build/panel/mixtarrvs-panel"
if [[ -x "$panel_src" ]]; then
  copy_desktop_binary mixtarrvs-panel "$panel_src"
else
  echo "graphical-rootfs: warning: missing Mixtar panel $panel_src" >&2
fi

build_ailang_ui_smoke

build_xwayland_wrapper

cp "$rootfs_dir/System/Runtime/Desktop/Xwayland" "$rootfs_dir/System/Tools/Xwayland"
cp "$rootfs_dir/System/Runtime/Desktop/xkbcomp" "$rootfs_dir/System/Tools/xkbcomp"
cp "$rootfs_dir/System/Runtime/Desktop/xauth" "$rootfs_dir/System/Tools/xauth"
cp "$rootfs_dir/System/Runtime/Desktop/xterm" "$rootfs_dir/System/Tools/xterm"
if [[ "$desktop_profile" == "rich" ]]; then
  cp "$rootfs_dir/System/Runtime/Desktop/dbus-daemon" "$rootfs_dir/System/Tools/dbus-daemon"
  cp "$rootfs_dir/System/Runtime/Desktop/mddm" "$rootfs_dir/System/Tools/mddm"
  cp "$rootfs_dir/System/Runtime/Desktop/mixtar-shell" "$rootfs_dir/System/Tools/mixtar-shell"
fi
chmod 0755 "$rootfs_dir/System/Tools/Xwayland"
chmod 0755 "$rootfs_dir/System/Tools/xkbcomp"
chmod 0755 "$rootfs_dir/System/Tools/xauth"
chmod 0755 "$rootfs_dir/System/Tools/xterm"
if [[ "$desktop_profile" == "rich" ]]; then
  chmod 0755 "$rootfs_dir/System/Tools/dbus-daemon"
  chmod 0755 "$rootfs_dir/System/Tools/mddm"
  chmod 0755 "$rootfs_dir/System/Tools/mixtar-shell"
fi

copy_optional_resource_tree /usr/share/labwc "$rootfs_dir/System/Resources/labwc"
copy_resource_tree /usr/share/X11/xkb "$rootfs_dir/System/Resources/X11/xkb"
mkdir -p "$rootfs_dir/System/Resources/X11/xkb/compiled"
chmod 01777 "$rootfs_dir/System/Resources/X11/xkb/compiled"
copy_resource_tree /usr/share/X11/locale "$rootfs_dir/System/Resources/X11/locale"
copy_resource_tree /usr/share/libinput "$rootfs_dir/System/Resources/libinput"
copy_resource_tree /usr/share/fontconfig "$rootfs_dir/System/Resources/fontconfig"
copy_resource_tree /usr/share/glib-2.0 "$rootfs_dir/System/Resources/glib-2.0"
copy_resource_tree /usr/share/fonts/truetype/dejavu \
  "$rootfs_dir/System/Resources/fonts/truetype/dejavu"
copy_resource_tree /etc/fonts "$rootfs_dir/System/Config/fonts"
copy_optional_resource_tree /usr/lib/locale/C.utf8 \
  "$rootfs_dir/System/Libraries/locale/C.utf8"
copy_optional_resource_tree /usr/lib/locale/C.UTF-8 \
  "$rootfs_dir/System/Libraries/locale/C.UTF-8"
if [[ -f /usr/share/zoneinfo/Europe/Warsaw ]]; then
  mkdir -p "$rootfs_dir/usr/share/zoneinfo/Europe" "$rootfs_dir/System/Config"
  cp /usr/share/zoneinfo/Europe/Warsaw \
    "$rootfs_dir/usr/share/zoneinfo/Europe/Warsaw"
  cp /usr/share/zoneinfo/Europe/Warsaw "$rootfs_dir/System/Config/localtime"
  chmod 0644 \
    "$rootfs_dir/usr/share/zoneinfo/Europe/Warsaw" \
    "$rootfs_dir/System/Config/localtime"
else
  echo "graphical-rootfs: warning: missing Europe/Warsaw zoneinfo" >&2
fi
if [[ "$desktop_profile" == "rich" ]]; then
  copy_optional_resource_tree "$mddm_repo/mddm/cursors/mixtar-aero" \
    "$rootfs_dir/System/Resources/icons/mixtar-aero"
  copy_optional_resource_tree /usr/share/icons/Adwaita \
    "$rootfs_dir/System/Resources/icons/Adwaita"
  copy_optional_resource_tree /usr/share/icons/hicolor \
    "$rootfs_dir/System/Resources/icons/hicolor"
fi
copy_optional_resource_tree /etc/X11/app-defaults "$rootfs_dir/System/Config/X11/app-defaults"

if [[ "$desktop_profile" == "rich" ]]; then
  dbus_profile="session-daemon"
  if [[ "$mddm_auth_test_mode" == "OFF" || "$mddm_auth_test_mode" == "0" ]]; then
    mddm_profile="login-auth-pam"
  else
    mddm_profile="login-auth-smoke"
  fi
else
  dbus_profile="none"
  mddm_profile="auth-gated-rich-profile"
fi

cat > "$rootfs_dir/System/Config/desktop-profile" <<EOF
PROFILE=graphical-$desktop_profile
SESSION=labwc-panel
COMPOSITOR=labwc
X11_COMPAT=Xwayland
X11_AUTH=Xauthority
DBUS=$dbus_profile
TERMINAL=xterm
MDDM=$mddm_profile
SMOKE=xdpyinfo
EOF

(
  cd "$rootfs_dir"
  find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9
) > "$image"

printf 'graphical-rootfs: base %s\n' "$base_image"
printf 'graphical-rootfs: wrote %s\n' "$image"
printf 'graphical-rootfs: root %s\n' "$rootfs_dir"
