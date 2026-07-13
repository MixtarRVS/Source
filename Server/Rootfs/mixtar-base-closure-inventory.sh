#!/bin/sh
set -eu

tools_dir="/System/Tools/MixtarRVS/bin"
source_list="/System/Config/MixtarRVS/userland-source-tools.txt"

line() {
  printf '%s\n' "$*"
}

section() {
  line ""
  line "== $* =="
}

path_status() {
  path="$1"
  if [ -L "$path" ]; then
    line "link $path -> $(readlink "$path")"
  elif [ -d "$path" ]; then
    line "dir  $path"
  elif [ -f "$path" ]; then
    line "file $path"
  elif [ -e "$path" ]; then
    line "node $path"
  else
    line "miss $path"
  fi
}

resolve_cmd() {
  cmd="$1"
  resolved=$(PATH="/System/Tools/MixtarRVS/bin:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin" command -v "$cmd" 2>/dev/null || true)
  if [ -n "$resolved" ]; then
    line "$cmd -> $resolved"
  else
    line "$cmd -> missing"
  fi
}

owner_hint() {
  path="$1"
  if command -v apk >/dev/null 2>&1; then
    apk info -W "$path" 2>/dev/null | sed 's/^/  apk-owner: /' || true
  fi
}

binary_closure() {
  label="$1"
  path="$2"
  if [ ! -e "$path" ]; then
    line "$label: missing $path"
    return
  fi

  line "$label: $path"
  owner_hint "$path"
  if command -v ldd >/dev/null 2>&1; then
    ldd "$path" 2>/dev/null | sed 's/^/  ldd: /' || true
  else
    line "  ldd: missing"
  fi
}

service_status() {
  name="$1"
  if [ -e "/etc/init.d/$name" ]; then
    target=$(readlink "/etc/runlevels/default/$name" 2>/dev/null || true)
    if [ -n "$target" ]; then
      line "$name: enabled -> $target"
    else
      line "$name: present"
    fi
  else
    line "$name: missing"
  fi
}

mounted_status() {
  path="$1"
  if [ -r /proc/mounts ] && grep -q " $path " /proc/mounts; then
    line "$path: mounted"
  else
    line "$path: not-mounted-or-unknown"
  fi
}

line "MixtarRVS base-closure inventory"
line "kernel: $(uname -r)"
line "machine: $(uname -m)"

section "Mixtar-owned userland"
if [ -d "$tools_dir" ]; then
  tool_count=$(find "$tools_dir" -type f -perm -111 | wc -l | tr -d ' ')
  line "tools_dir: $tools_dir"
  line "tools_count: $tool_count"
else
  line "tools_dir: missing $tools_dir"
fi
if [ -r "$source_list" ]; then
  source_count=$(wc -l < "$source_list" | tr -d ' ')
  line "source_list: $source_list"
  line "source_count: $source_count"
else
  line "source_list: missing $source_list"
fi
for cmd in uname ls cat cp mv rm grep sed awk ps find sort wc chmod ln mkdir rmdir; do
  resolve_cmd "$cmd"
done

section "Visible Mixtar layout"
for path in /Applications /Compatibility /Programs /System /Temporary /Users /Volumes; do
  path_status "$path"
done

section "Mixtar runtime libraries"
path_status /System/Libraries
path_status /etc/ld-musl-x86_64.path
if [ -r /etc/ld-musl-x86_64.path ]; then
  line "loader_path:"
  sed 's/^/  /' /etc/ld-musl-x86_64.path
fi
if [ -r /System/Config/MixtarRVS/runtime-library-required-paths.txt ]; then
  line "required_paths: $(wc -l < /System/Config/MixtarRVS/runtime-library-required-paths.txt | tr -d ' ')"
else
  line "required_paths: missing"
fi
if [ -r /System/Config/MixtarRVS/runtime-library-closure.manifest ]; then
  line "copied_entries: $(wc -l < /System/Config/MixtarRVS/runtime-library-closure.manifest | tr -d ' ')"
else
  line "copied_entries: missing"
fi
for lib in \
  /System/Libraries/ld-musl-x86_64.so.1 \
  /System/Libraries/libfts.so.0 \
  /System/Libraries/libcrypto.so.3 \
  /System/Libraries/librc.so.1 \
  /System/Libraries/libeinfo.so.1 \
  /System/Libraries/libdbus-1.so.3
do
  path_status "$lib"
done

section "POSIX/bootstrap compatibility layout"
for path in /bin /sbin /lib /usr/bin /usr/sbin /usr/lib /etc /run /dev /proc /sys; do
  path_status "$path"
done

section "Runtime mountpoints"
if [ -x /System/SystemTools/mixtar-runtime-mounts ]; then
  /System/SystemTools/mixtar-runtime-mounts status 2>/dev/null || true
else
  line "/System/SystemTools/mixtar-runtime-mounts: missing"
fi
for path in /dev /proc /sys /run; do
  mounted_status "$path"
done

section "Init surface"
if [ -x /System/SystemTools/init ]; then
  /System/SystemTools/init contract 2>/dev/null | sed 's/^/  /' || true
  /System/SystemTools/init check 2>/dev/null | sed 's/^/  /' || true
else
  line "/System/SystemTools/init: missing"
fi

section "Initramfs handoff surface"
if [ -x /System/SystemTools/mixtar-initramfs-handoff ]; then
  /System/SystemTools/mixtar-initramfs-handoff contract 2>/dev/null | sed 's/^/  /' || true
  /System/SystemTools/mixtar-initramfs-handoff check 2>/dev/null | sed 's/^/  /' || true
else
  line "/System/SystemTools/mixtar-initramfs-handoff: missing"
fi

section "Core binary closure"
binary_closure "mixtar-uname" "/System/Tools/MixtarRVS/bin/uname"
binary_closure "mixtar-ls" "/System/Tools/MixtarRVS/bin/ls"
binary_closure "shell-bootstrap" "/bin/sh"
binary_closure "init-bootstrap" "/sbin/init"
binary_closure "openrc-bootstrap" "/sbin/openrc"
binary_closure "sshd-bootstrap" "/usr/sbin/sshd"
binary_closure "dhcpcd-bootstrap" "/sbin/dhcpcd"

section "OpenRC/bootstrap service surface"
if [ -x /System/SystemTools/mixtar-service ]; then
  /System/SystemTools/mixtar-service backend 2>/dev/null | sed 's/^/mixtar-service-backend: /' || true
  /System/SystemTools/mixtar-service list 2>/dev/null | sed 's/^/  /' || true
else
  line "/System/SystemTools/mixtar-service: missing"
fi
if [ -d /etc/runlevels/default ]; then
  find /etc/runlevels/default -maxdepth 1 -mindepth 1 -type l -printf '%f -> %l\n' 2>/dev/null | sort || true
else
  line "/etc/runlevels/default: missing"
fi
for svc in iwd dhcpcd sshd dbus localmount fsck root mixtar-firstboot-report; do
  service_status "$svc"
done

section "Mixtar supervisor surface"
if [ -x /System/SystemTools/mixtar-supervisor ]; then
  /System/SystemTools/mixtar-supervisor contract 2>/dev/null | sed 's/^/  /' || true
  /System/SystemTools/mixtar-supervisor check 2>/dev/null | sed 's/^/  /' || true
  /System/SystemTools/mixtar-supervisor list 2>/dev/null | sed 's/^/  /' || true
else
  line "/System/SystemTools/mixtar-supervisor: missing"
fi

section "Network surface"
if [ -x /System/SystemTools/mixtar-network ]; then
  /System/SystemTools/mixtar-network status 2>/dev/null | sed 's/^/  /' || true
else
  line "/System/SystemTools/mixtar-network: missing"
fi

section "Network closure surface"
if [ -x /System/SystemTools/mixtar-network-closure ]; then
  /System/SystemTools/mixtar-network-closure status 2>/dev/null | sed 's/^/  /' || true
else
  line "/System/SystemTools/mixtar-network-closure: missing"
fi

section "Remote access surface"
if [ -x /System/SystemTools/mixtar-remote ]; then
  /System/SystemTools/mixtar-remote status 2>/dev/null | sed 's/^/  /' || true
else
  line "/System/SystemTools/mixtar-remote: missing"
fi

section "Remote closure surface"
if [ -x /System/SystemTools/mixtar-remote-closure ]; then
  /System/SystemTools/mixtar-remote-closure status 2>/dev/null | sed 's/^/  /' || true
else
  line "/System/SystemTools/mixtar-remote-closure: missing"
fi

section "Required replacement queue"
line "1. /System/SystemTools/init: DONE as non-active Mixtar init shim candidate over OpenRC bootstrap; boot activation still pending."
line "2. /System/SystemTools/mixtar-runtime-mounts: DONE as explicit runtime mount setup/status tool; activation waits for init stage."
line "3. /System/Libraries: DONE as explicit runtime library closure and active musl loader path."
line "4. /System/SystemTools/mixtar-service: DONE as Mixtar service surface over OpenRC bootstrap backend; native supervisor still pending."
line "5. /System/SystemTools/mixtar-network: DONE as Mixtar network status surface over iwd/dhcpcd bootstrap backend; native bring-up still pending."
line "6. /System/SystemTools/mixtar-remote: DONE as Mixtar remote status surface over OpenSSH bootstrap backend; native agent still pending."
line "7. /System/SystemTools/mixtar-initramfs-handoff: DONE as non-active handoff contract/check; activation still pending."
line "8. /System/SystemTools/mixtar-supervisor: DONE as non-active manifest supervisor candidate over OpenRC backend; activation still pending."
line "9. /System/SystemTools/mixtar-remote-closure: DONE as pinned OpenSSH remote closure; native remote agent still pending."
line "10. /System/SystemTools/mixtar-network-closure: DONE as pinned iwd/dhcpcd network closure; native network bring-up still pending."

section "Closure status"
line "userland: MixtarRVS source-built tools are primary when PATH starts with /System/Tools/MixtarRVS/bin."
line "bootstrap: Alpine/OpenRC/musl still provide init, shell fallback, libraries, services, network, ssh, and runtime mounts."
line "status: NOT CLOSED"
