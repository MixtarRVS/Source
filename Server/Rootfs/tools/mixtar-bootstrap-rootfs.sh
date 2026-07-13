#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
usage:
  mixtar-bootstrap-rootfs.sh build [output-dir]
  mixtar-bootstrap-rootfs.sh build-alpine [output-dir]
  mixtar-bootstrap-rootfs.sh show [output-dir]

Builds pre-v0 Mixtar rootfs artifacts. It does not modify the host root
filesystem and does not install Mixtar onto a disk.

Optional first-user environment:
  MIXTAR_FIRST_USER=vxz
  MIXTAR_FIRST_PASSWORD_HASH='$6$...'

No default password is baked into the artifact. If MIXTAR_FIRST_USER is omitted,
root remains locked and the rescue boot entry should be used for first boot.
EOF
}

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

command_name="${1:-build}"

case "$command_name" in
  build-alpine)
    output_arg="${2:-out/mixtar-bootstrap-alpine}"
    ;;
  *)
    output_arg="${2:-out/mixtar-bootstrap}"
    ;;
esac

case "$command_name" in
  build|build-alpine|show|help) ;;
  *) usage; die "unknown command: $command_name" ;;
esac

if [ "$command_name" = "help" ]; then
  usage
  exit 0
fi

case "$output_arg" in
  ""|"/"|"/."|"/.."|"/bin"|"/sbin"|"/usr"|"/etc"|"/lib"|"/home"|"/root"|"/var"|"/tmp")
    die "refusing unsafe output path: $output_arg"
    ;;
esac

mkdir -p "$output_arg"
output_dir=$(cd "$output_arg" && pwd)

case "$output_dir" in
  "/"|"/bin"|"/sbin"|"/usr"|"/etc"|"/lib"|"/home"|"/root"|"/var"|"/tmp")
    die "refusing unsafe resolved output path: $output_dir"
    ;;
esac

rootfs="$output_dir/rootfs"
layout_generation="$output_dir/generations/0001-layout-only"
alpine_generation="$output_dir/generations/0002-alpine-openrc"
image_dir="$output_dir/images"
first_user="${MIXTAR_FIRST_USER:-}"
first_password_hash="${MIXTAR_FIRST_PASSWORD_HASH:-}"

safe_link() {
  target="$1"
  link="$2"

  if [ -e "$link" ] && [ ! -L "$link" ]; then
    die "refusing to replace non-symlink: $link"
  fi

  ln -sfn "$target" "$link"
}

root_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required for this step"
    sudo "$@"
  fi
}

need_tool() {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

find_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    command -v "$1"
    return 0
  fi

  if [ -x "/usr/sbin/$1" ]; then
    printf '%s\n' "/usr/sbin/$1"
    return 0
  fi

  if [ -x "/sbin/$1" ]; then
    printf '%s\n' "/sbin/$1"
    return 0
  fi

  return 1
}

write_file() {
  path="$1"
  shift
  dir=$(dirname "$path")
  tmp="$output_dir/.mixtar-write.$$"

  mkdir -p "$dir" 2>/dev/null || root_cmd mkdir -p "$dir"
  printf '%s\n' "$@" > "$tmp"

  if ! cp "$tmp" "$path" 2>/dev/null; then
    root_cmd cp "$tmp" "$path"
  fi

  rm -f "$tmp"
}

show_tree() {
  find "$output_dir" -maxdepth 4 -mindepth 1 | sort | sed -n '1,160p'
}

fetch_alpine_minirootfs() {
  cache_dir="$output_dir/cache/alpine"
  mkdir -p "$cache_dir"

  releases="$cache_dir/latest-releases.yaml"
  curl -fsSL \
    https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml \
    -o "$releases"

  alpine_file=$(awk '$1 == "file:" && $2 ~ /^alpine-minirootfs-.*x86_64\.tar\.gz$/ { print $2; exit }' "$releases")
  [ -n "$alpine_file" ] || die "could not find Alpine minirootfs in latest-releases.yaml"

  alpine_sha=$(awk -v file="$alpine_file" '$1 == "file:" { in_file=($2 == file) } in_file && $1 == "sha256:" { print $2; exit }' "$releases")
  [ -n "$alpine_sha" ] || die "could not find sha256 for $alpine_file"

  alpine_url="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/$alpine_file"
  alpine_tarball="$cache_dir/$alpine_file"

  if [ ! -f "$alpine_tarball" ]; then
    curl -fL "$alpine_url" -o "$alpine_tarball"
  fi

  printf '%s  %s\n' "$alpine_sha" "$alpine_tarball" | sha256sum -c -
}

apply_layout_only_identity() {
  mkdir -p \
    "$rootfs/Applications" \
    "$rootfs/Programs" \
    "$rootfs/Users/Administrator" \
    "$rootfs/Volumes" \
    "$rootfs/Temporary" \
    "$rootfs/Compatibility/Debian" \
    "$rootfs/Compatibility/Alpine" \
    "$rootfs/Compatibility/Chimera" \
    "$rootfs/Compatibility/FreeBSD" \
    "$rootfs/Compatibility/OpenBSD" \
    "$rootfs/Compatibility/Void" \
    "$rootfs/System/Kernel" \
    "$rootfs/System/Runtime/run" \
    "$rootfs/System/Init" \
    "$rootfs/System/Tools" \
    "$rootfs/System/SystemTools" \
    "$rootfs/System/Shells" \
    "$rootfs/System/Libraries" \
    "$rootfs/System/Config" \
    "$rootfs/System/Resources" \
    "$rootfs/System/Logs" \
    "$rootfs/System/Packages" \
    "$rootfs/usr" \
    "$rootfs/var" \
    "$layout_generation"

  safe_link "Administrator" "$rootfs/Users/Superuser"
  safe_link "Administrator" "$rootfs/Users/root"

  safe_link "System/Tools" "$rootfs/bin"
  safe_link "System/SystemTools" "$rootfs/sbin"
  safe_link "System/Libraries" "$rootfs/lib"
  safe_link "System/Config" "$rootfs/etc"
  safe_link "System/Runtime/run" "$rootfs/run"
  safe_link "Temporary" "$rootfs/tmp"
  safe_link "Users" "$rootfs/home"
  safe_link "Users/Administrator" "$rootfs/root"

  safe_link "../System/Tools" "$rootfs/usr/bin"
  safe_link "../System/SystemTools" "$rootfs/usr/sbin"
  safe_link "../System/Libraries" "$rootfs/usr/lib"
  safe_link "../System/Resources" "$rootfs/usr/share"
  safe_link "../System/Logs" "$rootfs/var/log"
  safe_link "../System/Runtime/run" "$rootfs/var/run"

  safe_link "/dev" "$rootfs/System/Devices"
  safe_link "/proc" "$rootfs/System/Process"
  safe_link "/sys" "$rootfs/System/Hardware"
}

apply_alpine_view_layout() {
  mkdir -p \
    "$rootfs/Applications" \
    "$rootfs/Programs" \
    "$rootfs/Users/Administrator" \
    "$rootfs/Volumes" \
    "$rootfs/Temporary" \
    "$rootfs/Compatibility/Debian" \
    "$rootfs/Compatibility/Alpine" \
    "$rootfs/Compatibility/Chimera" \
    "$rootfs/Compatibility/FreeBSD" \
    "$rootfs/Compatibility/OpenBSD" \
    "$rootfs/Compatibility/Void" \
    "$rootfs/System" \
    "$rootfs/System/Kernel" \
    "$rootfs/System/Runtime" \
    "$rootfs/System/Init" \
    "$rootfs/System/Shells" \
    "$rootfs/System/Logs" \
    "$rootfs/System/Packages"

  safe_link "../bin" "$rootfs/System/Tools"
  safe_link "../sbin" "$rootfs/System/SystemTools"
  safe_link "../lib" "$rootfs/System/Libraries"
  safe_link "../etc" "$rootfs/System/Config"
  safe_link "../usr/share" "$rootfs/System/Resources"
  safe_link "../../run" "$rootfs/System/Runtime/run"
  safe_link "../dev" "$rootfs/System/Devices"
  safe_link "../proc" "$rootfs/System/Process"
  safe_link "../sys" "$rootfs/System/Hardware"

  if [ -d "$rootfs/home" ] && [ ! -L "$rootfs/home" ]; then
    rmdir "$rootfs/home" 2>/dev/null || true
  fi
  if [ ! -e "$rootfs/home" ]; then
    safe_link "Users" "$rootfs/home"
  fi

  if [ -d "$rootfs/root" ] && [ ! -L "$rootfs/root" ]; then
    rmdir "$rootfs/root" 2>/dev/null || true
  fi
  if [ ! -e "$rootfs/root" ]; then
    safe_link "Users/Administrator" "$rootfs/root"
  fi

  safe_link "Administrator" "$rootfs/Users/Superuser"
  safe_link "Administrator" "$rootfs/Users/root"
  safe_link "../Tools/sh" "$rootfs/System/Shells/sh"
}

configure_alpine_login_shell() {
  shells_tmp="$output_dir/.mixtar-shells"
  passwd_tmp="$output_dir/.mixtar-passwd"
  motd_tmp="$output_dir/.mixtar-motd"

  write_file "$shells_tmp" \
    '/bin/sh' \
    '/bin/ash' \
    '/bin/zsh' \
    '/System/Shells/sh' \
    '/System/Shells/zsh'
  root_cmd cp "$shells_tmp" "$rootfs/etc/shells"

  awk -F: '
    BEGIN { OFS = FS }
    $1 == "root" {
      $6 = "/Users/Administrator"
      $7 = "/System/Shells/zsh"
    }
    { print }
  ' "$rootfs/etc/passwd" > "$passwd_tmp"
  root_cmd cp "$passwd_tmp" "$rootfs/etc/passwd"

  write_file "$motd_tmp" \
    'MixtarRVS pre-v0 Alpine/OpenRC/zsh bootstrap' \
    '' \
    'This is the first bootable rootfs artifact.' \
    'AILang and msh are intentionally absent in this generation.'
  root_cmd cp "$motd_tmp" "$rootfs/etc/motd"

  rm -f "$shells_tmp" "$passwd_tmp" "$motd_tmp"
}

validate_first_user_policy() {
  if [ -z "$first_user" ] && [ -n "$first_password_hash" ]; then
    die "MIXTAR_FIRST_PASSWORD_HASH requires MIXTAR_FIRST_USER"
  fi

  if [ -n "$first_user" ]; then
    printf '%s\n' "$first_user" | grep -Eq '^[a-z_][a-z0-9_-]*$' || die "invalid MIXTAR_FIRST_USER: $first_user"
  fi

  if [ -n "$first_password_hash" ]; then
    case "$first_password_hash" in
      *"'"*|*"
"*)
        die "MIXTAR_FIRST_PASSWORD_HASH contains unsupported characters"
        ;;
    esac
  fi
}

configure_first_user() {
  [ -n "$first_user" ] || return 0

  first_user_script="$output_dir/.mixtar-first-user.sh"
  write_file "$first_user_script" \
    '#!/bin/sh' \
    'set -eu' \
    'user="$MIXTAR_FIRST_USER"' \
    'hash="${MIXTAR_FIRST_PASSWORD_HASH:-}"' \
    'home="/Users/$user"' \
    'if ! grep -q "^$user:" /etc/passwd; then' \
    '  adduser -D -h "$home" -s /System/Shells/zsh "$user"' \
    'fi' \
    'awk -F: -v user="$user" -v shell_path="/System/Shells/zsh" '"'"'BEGIN { OFS = FS } $1 == user { $7 = shell_path } { print }'"'"' /etc/passwd > /etc/passwd.new' \
    'mv /etc/passwd.new /etc/passwd' \
    'mkdir -p "$home"' \
    'chown "$user:$user" "$home"' \
    'if [ -n "$hash" ]; then' \
    '  awk -F: -v user="$user" -v hash="$hash" '"'"'BEGIN { OFS = FS } $1 == user { $2 = hash } { print }'"'"' /etc/shadow > /etc/shadow.new' \
    '  mv /etc/shadow.new /etc/shadow' \
    'fi'

  root_cmd cp "$first_user_script" "$rootfs/tmp/mixtar-first-user.sh"
  root_cmd env \
    "MIXTAR_FIRST_USER=$first_user" \
    "MIXTAR_FIRST_PASSWORD_HASH=$first_password_hash" \
    "$chroot_tool" "$rootfs" /bin/sh /tmp/mixtar-first-user.sh
  root_cmd rm -f "$rootfs/tmp/mixtar-first-user.sh"
  rm -f "$first_user_script"
}

install_postboot_report() {
  report_tool="$rootfs/bin/mixtar-postboot-report"

  write_file "$report_tool" \
    '#!/bin/sh' \
    'set -eu' \
    'if [ "${MIXTAR_REPORT_STDOUT:-0}" != "1" ]; then' \
    '  mkdir -p /System/Logs 2>/dev/null || true' \
    '  MIXTAR_REPORT_STDOUT=1 "$0" "$@" > /System/Logs/firstboot-evidence.txt' \
    '  cat /System/Logs/firstboot-evidence.txt' \
    '  exit 0' \
    'fi' \
    '' \
    'line() {' \
    '  printf "%s\n" "$1"' \
    '}' \
    '' \
    'line "MixtarRVS post-boot report"' \
    'line ""' \
    'line "[kernel]"' \
    'uname -a || true' \
    'line ""' \
    'line "[release]"' \
    'cat /etc/mixtar-release 2>/dev/null || true' \
    'line ""' \
    'line "[alpine]"' \
    'cat /etc/alpine-release 2>/dev/null || true' \
    'apk --version 2>/dev/null || true' \
    'line ""' \
    'line "[init]"' \
    'readlink /sbin/init 2>/dev/null || ls -l /sbin/init 2>/dev/null || true' \
    'rc-status 2>/dev/null || true' \
    'line ""' \
    'line "[shell]"' \
    'ls -l /System/Shells/zsh 2>/dev/null || true' \
    'zsh --version 2>/dev/null || true' \
    'line ""' \
    'line "[layout]"' \
    'for path in /System /Applications /Programs /Users /Compatibility; do' \
    '  if [ -e "$path" ] || [ -L "$path" ]; then' \
    '    ls -ld "$path"' \
    '  else' \
    '    printf "missing %s\n" "$path"' \
    '  fi' \
    'done' \
    'line ""' \
    'line "[compatibility]"' \
    'ls -1 /Compatibility 2>/dev/null || true' \
    'for path in /Compatibility/Alpine /Compatibility/FreeBSD /Compatibility/OpenBSD; do' \
    '  if [ -e "$path" ] || [ -L "$path" ]; then' \
    '    ls -ld "$path"' \
    '  else' \
    '    printf "missing %s\n" "$path"' \
    '  fi' \
    'done' \
    'line ""' \
    'line "[generation]"' \
    'mixtar-generation-report 2>/dev/null || cat /System/Runtime/generation.env 2>/dev/null || true' \
    'line ""' \
    'line "[firstboot-verify]"' \
    'mixtar-firstboot-verify 2>&1 || true' \
    'line ""' \
    'line "[storage]"' \
    'findmnt / 2>/dev/null || mount | sed -n "1,8p" || true' \
    'line ""' \
    'line "[report]"' \
    'line "/System/Logs/firstboot-evidence.txt"'

  root_cmd chmod 755 "$report_tool"
}

install_firstboot_verifier() {
  verify_tool="$rootfs/bin/mixtar-firstboot-verify"

  write_file "$verify_tool" \
    '#!/bin/sh' \
    'set -eu' \
    'fail=0' \
    'ok() {' \
    '  printf "ok: %s\n" "$1"' \
    '}' \
    'bad() {' \
    '  printf "missing: %s\n" "$1"' \
    '  fail=1' \
    '}' \
    'need_cmd() {' \
    '  if command -v "$1" >/dev/null 2>&1; then ok "command $1"; else bad "command $1"; fi' \
    '}' \
    'need_path() {' \
    '  if [ -e "$1" ] || [ -L "$1" ]; then ok "$1"; else bad "$1"; fi' \
    '}' \
    'case "$(uname -s 2>/dev/null || true)" in' \
    '  Linux) ok "kernel Linux" ;;' \
    '  *) bad "kernel Linux" ;;' \
    'esac' \
    'need_cmd apk' \
    'need_cmd rc-status' \
    'need_cmd zsh' \
    'need_path /System' \
    'need_path /System/Current' \
    'need_path /System/Generations' \
    'need_path /System/Runtime' \
    'need_path /System/Runtime/generation.env' \
    'need_path /System/Tools' \
    'need_path /System/SystemTools' \
    'need_path /System/Shells' \
    'need_path /System/Shells/zsh' \
    'need_path /Applications' \
    'need_path /Programs' \
    'need_path /Users' \
    'need_path /Compatibility' \
    'need_path /Compatibility/Alpine' \
    'need_path /Compatibility/FreeBSD' \
    'need_path /Compatibility/OpenBSD' \
    'if [ -L /System/Current ]; then ok "/System/Current symlink"; else bad "/System/Current symlink"; fi' \
    'if grep -q "^MIXTAR_GENERATION_ID=" /System/Runtime/generation.env 2>/dev/null; then ok "generation id"; else bad "generation id"; fi' \
    'if command -v ailang >/dev/null 2>&1; then bad "ailang absent in pre-v0"; else ok "ailang absent in pre-v0"; fi' \
    'if command -v msh >/dev/null 2>&1 || [ -e /System/Shells/msh ] || [ -L /System/Shells/msh ]; then bad "msh absent in pre-v0"; else ok "msh absent in pre-v0"; fi' \
    'if [ "$fail" -eq 0 ]; then' \
    '  printf "%s\n" "firstboot-verification=ok"' \
    'else' \
    '  printf "%s\n" "firstboot-verification=failed"' \
    'fi' \
    'exit "$fail"'

  root_cmd chmod 755 "$verify_tool"
}

install_firstboot_report_service() {
  service_file="$rootfs/etc/init.d/mixtar-firstboot-report"
  default_runlevel="$rootfs/etc/runlevels/default"

  root_cmd mkdir -p "$default_runlevel"

  write_file "$service_file" \
    '#!/sbin/openrc-run' \
    'description="MixtarRVS first boot evidence capture"' \
    '' \
    'depend() {' \
    '  need localmount' \
    '  after bootmisc' \
    '}' \
    '' \
    'start() {' \
    '  ebegin "Capturing MixtarRVS first boot evidence"' \
    '  mkdir -p /System/Logs 2>/dev/null || true' \
    '  /System/Tools/mixtar-postboot-report > /System/Logs/firstboot-report.service.log 2>&1 || true' \
    '  eend 0' \
    '}'

  root_cmd chmod 755 "$service_file"

  if [ -L "$default_runlevel/mixtar-firstboot-report" ]; then
    root_cmd rm "$default_runlevel/mixtar-firstboot-report"
  fi
  if [ ! -e "$default_runlevel/mixtar-firstboot-report" ]; then
    root_cmd ln -s /etc/init.d/mixtar-firstboot-report "$default_runlevel/mixtar-firstboot-report"
  fi
}

install_remote_access() {
  ssh_dropin="$rootfs/etc/ssh/sshd_config.d/mixtar-pre-v0.conf"
  iwd_main="$rootfs/etc/iwd/main.conf"
  default_runlevel="$rootfs/etc/runlevels/default"

  root_cmd mkdir -p "$rootfs/etc/ssh/sshd_config.d" "$rootfs/etc/iwd" "$default_runlevel"

  write_file "$ssh_dropin" \
    'PermitRootLogin no' \
    'PasswordAuthentication yes' \
    'PubkeyAuthentication yes' \
    'AuthorizedKeysFile .ssh/authorized_keys'

  if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/\*.conf' "$rootfs/etc/ssh/sshd_config" 2>/dev/null; then
    root_cmd sh -c "printf '%s\n' 'Include /etc/ssh/sshd_config.d/*.conf' >> '$rootfs/etc/ssh/sshd_config'"
  fi

  if ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    root_cmd cp /etc/ssh/ssh_host_*_key "$rootfs/etc/ssh/" 2>/dev/null || true
    root_cmd cp /etc/ssh/ssh_host_*_key.pub "$rootfs/etc/ssh/" 2>/dev/null || true
    root_cmd sh -c "chmod 600 '$rootfs'/etc/ssh/ssh_host_*_key 2>/dev/null || true"
    root_cmd sh -c "chmod 644 '$rootfs'/etc/ssh/ssh_host_*_key.pub 2>/dev/null || true"
  else
    root_cmd "$chroot_tool" "$rootfs" /usr/bin/ssh-keygen -A
  fi

  if [ -n "$first_user" ] && [ -f "/home/$first_user/.ssh/authorized_keys" ]; then
    root_cmd mkdir -p "$rootfs/Users/$first_user/.ssh"
    root_cmd cp "/home/$first_user/.ssh/authorized_keys" "$rootfs/Users/$first_user/.ssh/authorized_keys"
    root_cmd chmod 700 "$rootfs/Users/$first_user/.ssh"
    root_cmd chmod 600 "$rootfs/Users/$first_user/.ssh/authorized_keys"
    root_cmd "$chroot_tool" "$rootfs" chown -R "$first_user:$first_user" "/Users/$first_user/.ssh" 2>/dev/null || true
  fi

  if [ -d /etc/iwd ]; then
    root_cmd cp -a /etc/iwd/. "$rootfs/etc/iwd/" 2>/dev/null || true
  fi
  if [ -d /var/lib/iwd ]; then
    root_cmd mkdir -p "$rootfs/var/lib/iwd"
    root_cmd cp -a /var/lib/iwd/. "$rootfs/var/lib/iwd/" 2>/dev/null || true
    root_cmd sh -c "chmod 600 '$rootfs'/var/lib/iwd/* 2>/dev/null || true"
  fi

  if [ ! -f "$iwd_main" ]; then
    write_file "$iwd_main" \
      '[General]' \
      'EnableNetworkConfiguration=true' \
      '[Network]' \
      'EnableIPv6=true'
  fi

  for service in iwd dhcpcd sshd; do
    if [ -f "$rootfs/etc/init.d/$service" ] && [ ! -e "$default_runlevel/$service" ]; then
      root_cmd ln -s "/etc/init.d/$service" "$default_runlevel/$service"
    fi
  done
}

install_generation_contract() {
  generation_id="0002-alpine-openrc-zsh"
  generation_dir="$rootfs/System/Generations/$generation_id"
  report_tool="$rootfs/bin/mixtar-generation-report"

  root_cmd mkdir -p "$generation_dir" "$rootfs/System/Runtime"

  write_file "$rootfs/System/Runtime/generation.env" \
    "MIXTAR_GENERATION_ID=$generation_id" \
    'MIXTAR_GENERATION_KIND=pre-v0-rootfs' \
    'MIXTAR_SUBSTRATE=alpine-minirootfs' \
    'MIXTAR_LIBC=musl' \
    'MIXTAR_PACKAGE_BACKEND=apk' \
    'MIXTAR_INIT=openrc' \
    'MIXTAR_USER_SHELL=zsh' \
    'MIXTAR_AILANG=absent' \
    'MIXTAR_MSH=absent'

  write_file "$generation_dir/manifest.json" \
    '{' \
    "  \"generation_id\": \"$generation_id\"," \
    '  "kind": "pre-v0-rootfs",' \
    '  "substrate": "alpine-minirootfs",' \
    '  "libc": "musl",' \
    '  "package_backend": "apk",' \
    '  "init": "openrc",' \
    '  "user_shell": "zsh",' \
    '  "layout_mode": "bootstrap-view",' \
    '  "contains_ailang": false,' \
    '  "contains_msh": false,' \
    '  "native_paths": ["/System", "/Applications", "/Programs", "/Users", "/Compatibility"],' \
    '  "compatibility_paths": ["/Compatibility/Alpine", "/Compatibility/FreeBSD", "/Compatibility/OpenBSD"]' \
    '}'

  if [ -L "$rootfs/System/Current" ]; then
    root_cmd rm "$rootfs/System/Current"
  fi
  if [ ! -e "$rootfs/System/Current" ]; then
    root_cmd ln -s "Generations/$generation_id" "$rootfs/System/Current"
  fi

  write_file "$report_tool" \
    '#!/bin/sh' \
    'set -eu' \
    'printf "%s\n" "MixtarRVS generation report"' \
    'printf "%s\n" ""' \
    'cat /System/Runtime/generation.env 2>/dev/null || true' \
    'printf "%s\n" ""' \
    'printf "%s" "System/Current="' \
    'readlink /System/Current 2>/dev/null || printf "%s\n" "missing"' \
    'printf "%s\n" ""' \
    'cat /System/Current/manifest.json 2>/dev/null || true'

  root_cmd chmod 755 "$report_tool"
}

build_layout_only() {
  apply_layout_only_identity

  build_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  host_name=$(hostname 2>/dev/null || printf 'unknown')

  write_file "$rootfs/System/Config/mixtar-release" \
    'NAME=MixtarRVS' \
    'VERSION_ID=0.0.1-bootstrap' \
    'BUILD_STAGE=layout-only' \
    'AILANG=absent' \
    'MSH=absent'

  write_file "$rootfs/System/Config/compatibility-roots" \
    '/Compatibility/Debian' \
    '/Compatibility/Alpine' \
    '/Compatibility/Chimera' \
    '/Compatibility/FreeBSD' \
    '/Compatibility/OpenBSD' \
    '/Compatibility/Void'

  write_file "$rootfs/README.bootstrap" \
    'MixtarRVS pre-v0 rootfs skeleton' \
    '' \
    'This artifact is built by Server/Rootfs/tools/mixtar-bootstrap-rootfs.sh.' \
    'It is not installed onto the host system.' \
    'It contains no msh and no AILang runtime.'

  write_file "$layout_generation/manifest.json" \
    '{' \
    '  "name": "Mixtar pre-v0 layout-only bootstrap",' \
    '  "generation": "0001-layout-only",' \
    '  "target": "rootfs artifact",' \
    '  "layout_mode": "identity-skeleton",' \
    '  "contains_ailang": false,' \
    '  "contains_msh": false,' \
    '  "package_backend": "none",' \
    '  "native_paths": ["/System", "/Applications", "/Programs", "/Users", "/Compatibility"],' \
    '  "compatibility_roots": ["/Compatibility/Debian", "/Compatibility/Alpine", "/Compatibility/Chimera", "/Compatibility/FreeBSD", "/Compatibility/OpenBSD", "/Compatibility/Void"],' \
    "  \"built_at\": \"$build_time\"," \
    "  \"built_on\": \"$host_name\"" \
    '}'

  write_file "$output_dir/STATUS.txt" \
    'MixtarRVS pre-v0 bootstrap artifact' \
    '' \
    "Output: $output_dir" \
    'Scope: layout-only rootfs skeleton' \
    'AILang: absent' \
    'msh: absent' \
    'Package backend: none' \
    'Host mutation: none'

  printf '%s\n' "built: $output_dir"
  show_tree
}

build_alpine() {
  validate_first_user_policy

  need_tool curl
  need_tool awk
  need_tool tar
  need_tool sha256sum
  need_tool mksquashfs

  chroot_tool=$(find_tool chroot) || die "missing required tool: chroot"

  fetch_alpine_minirootfs

  image="$image_dir/mixtar-0002-alpine-openrc-rootfs.squashfs"

  root_cmd rm -rf "$rootfs" "$alpine_generation" "$image"
  mkdir -p "$rootfs" "$alpine_generation" "$image_dir"
  tar -xzf "$alpine_tarball" -C "$rootfs"

  apply_alpine_view_layout

  if [ -f /etc/resolv.conf ]; then
    cp /etc/resolv.conf "$rootfs/etc/resolv.conf"
  fi

  root_cmd "$chroot_tool" "$rootfs" /sbin/apk add --no-cache alpine-base openrc zsh openssh iwd dhcpcd

  safe_link "../Tools/zsh" "$rootfs/System/Shells/zsh"
  configure_alpine_login_shell
  configure_first_user
  install_remote_access
  install_generation_contract
  install_firstboot_verifier
  install_postboot_report
  install_firstboot_report_service

  write_file "$rootfs/etc/mixtar-release" \
    'NAME=MixtarRVS' \
    'VERSION_ID=0.0.2-alpine-openrc' \
    'BUILD_STAGE=alpine-openrc-bootstrap' \
    'LAYOUT_MODE=bootstrap-view' \
    'LIBC=musl' \
    'PACKAGE_BACKEND=apk' \
    'INIT=openrc' \
    'USER_SHELL=zsh' \
    "FIRST_USER=${first_user:-absent}" \
    'AILANG=absent' \
    'MSH=absent'

  write_file "$rootfs/etc/mixtar-compatibility-roots" \
    '/Compatibility/Debian' \
    '/Compatibility/Alpine' \
    '/Compatibility/Chimera' \
    '/Compatibility/FreeBSD' \
    '/Compatibility/OpenBSD' \
    '/Compatibility/Void'

  build_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  host_name=$(hostname 2>/dev/null || printf 'unknown')
  rootfs_size=$(du -sh "$rootfs" | awk '{ print $1 }')

  write_file "$alpine_generation/manifest.json" \
    '{' \
    '  "name": "Mixtar pre-v0 Alpine/OpenRC/zsh bootstrap",' \
    '  "generation": "0002-alpine-openrc",' \
    '  "target": "rootfs artifact",' \
    '  "layout_mode": "bootstrap-view",' \
    '  "substrate": "alpine-minirootfs",' \
    '  "libc": "musl",' \
    '  "package_backend": "apk",' \
    '  "init": "openrc",' \
    '  "user_shell": "zsh",' \
    "  \"first_user\": \"${first_user:-absent}\"," \
    '  "contains_ailang": false,' \
    '  "contains_msh": false,' \
    '  "native_paths": ["/System", "/Applications", "/Programs", "/Users", "/Compatibility"],' \
    '  "compatibility_roots": ["/Compatibility/Debian", "/Compatibility/Alpine", "/Compatibility/Chimera", "/Compatibility/FreeBSD", "/Compatibility/OpenBSD", "/Compatibility/Void"],' \
    "  \"alpine_file\": \"$alpine_file\"," \
    "  \"rootfs_size\": \"$rootfs_size\"," \
    "  \"built_at\": \"$build_time\"," \
    "  \"built_on\": \"$host_name\"" \
    '}'

  write_file "$output_dir/STATUS.txt" \
    'MixtarRVS pre-v0 Alpine/OpenRC bootstrap artifact' \
    '' \
    "Output: $output_dir" \
    'Scope: Alpine minirootfs + OpenRC + zsh + Mixtar view layout' \
    'AILang: absent' \
    'msh: absent' \
    'Package backend: apk' \
    'Init: OpenRC' \
    'Host mutation: package cache only; target rootfs remains an artifact'

  root_cmd chown -hR 0:0 "$rootfs"
  root_cmd mksquashfs "$rootfs" "$image" -noappend -comp zstd -Xcompression-level 15 >/dev/null

  if [ "$(id -u)" -ne 0 ]; then
    sudo chown "$(id -u):$(id -g)" "$image"
  fi

  printf '%s\n' "built: $output_dir"
  printf '%s\n' "image: $image"
  ls -lh "$image"
  show_tree
}

if [ "$command_name" = "show" ]; then
  show_tree
  exit 0
fi

case "$command_name" in
  build)
    build_layout_only
    ;;
  build-alpine)
    build_alpine
    ;;
esac
