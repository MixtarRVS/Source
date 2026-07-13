#!/usr/bin/env python3
"""MixtarRVS musl build/install helper for the BSD Toolkit.

This script is intentionally driven from toolkit_build.ail. It turns the
existing AILang-owned Toolkit build plans into a repeatable musl-native remote
build/install path for the current MixtarRVS laptop image.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import tarfile
from pathlib import Path


REPO = Path(__file__).resolve().parents[5]
OUT = REPO / "out" / "mixtarrvs-musl"
PACKAGE = OUT / "mixtarrvs-musl-src.tar.gz"
REMOTE_DEFAULT = "vxz@192.168.99.110"
REMOTE_TARBALL = "/tmp/mixtarrvs-musl-src.tar.gz"
REMOTE_BUILD = "/tmp/mixtarrvs-musl-build"

BASE_TOOLS = [
    "echo", "cat", "pwd", "true", "false", "mkdir", "rmdir", "cp", "ls",
    "mv", "rm", "uname", "test", "chmod", "ln", "date", "wc", "grep",
    "sed", "basename", "dirname", "env", "head", "tee", "touch",
    "readlink", "id", "uniq", "cut", "printenv", "yes", "tty", "seq",
    "mktemp",
]

SOURCE_TOOLS = [
    "echo", "cat", "pwd", "true", "false", "mkdir", "rmdir", "cp", "ls",
    "mv", "rm", "domainname", "hostname", "realpath", "sleep", "sync",
    "chmod", "test", "env", "dirname", "basename", "head", "tee", "touch",
    "readlink", "uname", "id", "date", "uniq", "wc", "ln", "cut", "sed",
    "arch", "printenv", "yes", "tty", "rev", "seq", "mktemp", "paste",
    "comm", "fold", "nice", "what", "cal", "hexdump", "kill", "getopt",
    "fmt", "split", "logname", "nohup", "timeout", "unexpand", "column",
    "col", "rs", "from", "banner", "cmp", "colrm", "expand", "join", "tr",
    "apply", "expr", "jot", "csplit", "chroot", "dd", "du", "locale",
    "logger", "look", "nologin", "ed", "nproc", "pr", "printf", "renice",
    "sdiff", "stat", "ul", "grep", "tail", "find", "xargs", "which",
    "script", "nl", "rmt", "mt", "shutdown", "reboot", "users", "wall", "df", "mknod",
    "tsort", "who", "w", "vmstat", "diff", "patch", "getconf", "zic", "zdump", "file",
    "sort", "m4", "awk", "diff3", "gencat", "gprof", "ipcrm", "ipcs", "stty", "pkill",
    "ps", "dmesg", "getent", "nm", "rpcgen", "uuidgen", "freebsd-version",
    "chflags", "pwait", "cpuset", "kenv", "getfacl", "setfacl", "chio",
    "pax", "csh", "sh", "pkgconf", "yacc", "lex", "watch", "less", "vi", "vipw", "umount", "mount", "fsck", "init", "sysctl", "swapon", "ping", "top", "fdisk", "cron", "adduser", "su", "passwd", "login",
]

MINIMUM_EXTRA_TOOLS = [
    "sleep", "hostname", "realpath", "which", "printf", "tail", "find",
    "xargs", "cmp", "df", "du", "stat", "hexdump", "split", "tr",
    "join", "comm", "fold", "paste", "expr", "getopt", "arch", "rev",
    "sync", "domainname", "kill", "nice", "timeout", "logname",
]

GROUPS = {
    "all": SOURCE_TOOLS,
    "tier-a": SOURCE_TOOLS,
    "source": SOURCE_TOOLS,
    "core": SOURCE_TOOLS,
    "base": BASE_TOOLS,
    "minimum": BASE_TOOLS + MINIMUM_EXTRA_TOOLS,
    "extra": MINIMUM_EXTRA_TOOLS,
}

BOOT_CRITICAL_TOOLS = [
    "sh", "init", "mount", "umount", "fsck", "reboot", "shutdown", "swapon",
    "sysctl", "fdisk", "cron", "adduser", "su", "passwd", "login", "top",
    "ping",
]

BOOT_COMPAT_ROOT = "/Compatibility/POSIX/Alpine/3.24"
BOOT_COMPAT_BUSYBOX_APPLETS = [
    "sh", "mount", "umount", "mkdir", "rmdir", "ln", "rm", "cp", "mv",
    "cat", "chmod", "chown", "grep", "sed", "awk", "sleep", "true",
    "false", "echo", "uname", "dmesg", "ps", "kill", "hostname", "sync",
]
BOOT_COMPAT_SBIN_BUSYBOX_APPLETS = [
    "mount", "umount", "mdev", "modprobe", "depmod", "ifconfig", "ip",
    "route",
]


def remote_words(words: list[str]) -> str:
    return " ".join(f"'{word}'" for word in words)


def run(cmd: list[str], cwd: Path | None = None) -> None:
    subprocess.run(cmd, cwd=str(cwd or REPO), check=True)


def capture(cmd: list[str], cwd: Path | None = None) -> str:
    return subprocess.check_output(cmd, cwd=str(cwd or REPO), text=True)


def resolve_tools(selection: str) -> list[str]:
    if selection in GROUPS:
        tools = GROUPS[selection]
        return list(dict.fromkeys(tools))
    if "," in selection:
        tools = [tool.strip() for tool in selection.split(",") if tool.strip()]
        return list(dict.fromkeys(tools))
    return [selection]


def plan_for(tool: str) -> str:
    exe = REPO / "out" / "server" / "toolkit_build.exe"
    if not exe.exists():
        raise SystemExit(f"missing {exe}; build toolkit_build.exe first")
    text = capture([str(exe), "plan", tool])
    match = re.search(r"```sh\s*(.*?)\s*```", text, re.S)
    if not match:
        raise SystemExit(f"missing shell plan for {tool}")
    return match.group(1).strip()


def musl_command(tool: str) -> str:
    cmd = plan_for(tool)
    cmd = cmd.replace("cp System/Userland/Bridge/scripts/", "/bin/cp System/Userland/Bridge/scripts/")
    cmd = cmd.replace(" && chmod +x ", " && /bin/chmod 0755 ")
    cmd = cmd.replace(
        "System/Userland/Generated/targets/linux-x64/bin",
        "out/mixtarrvs-musl-target/bin",
    )
    cmd = cmd.replace(
        "System/Userland/Generated/targets/linux-x64/libexec",
        "out/mixtarrvs-musl-target/libexec",
    )
    cmd = cmd.replace(
        "cc -std=c23 ",
        "cc -std=c23 -Wno-unterminated-string-initialization ",
    )
    if tool == "dd" or tool == "rmt":
        cmd = cmd.replace("cc -std=c23 ", "cc -std=c23 -Wno-overflow ")
    if tool == "nl":
        cmd = cmd.replace("cc -std=c23 ", "cc -std=c23 -Wno-missing-braces ")
    if tool == "ps" or tool == "dmesg":
        cmd = cmd.replace("cc -std=c23 ", "cc -std=c23 -Wno-missing-braces ")
    if tool == "shutdown":
        cmd = cmd.replace("cc -std=c23 ", "cc -std=c23 -Wno-error=cpp ")
    if tool == "pkill" or tool == "ps":
        cmd = cmd.replace("cc -std=c23 ", "cc -std=c23 -Wno-error=cpp ")
    if tool == "wall":
        cmd = cmd.replace(
            "cc -std=c23 ",
            "cc -std=c23 -Wno-sizeof-pointer-memaccess -Wno-format-truncation ",
        )
    if tool == "uuidgen":
        cmd = cmd.replace("cc -std=c23 ", "cc -std=c23 -Wno-pointer-sign ")
    if tool == "pwait":
        cmd = cmd.replace("cc -std=c23 ", "cc -std=c23 -Wno-pedantic ")
    if tool == "cpuset":
        cmd = cmd.replace("cc -std=c23 ", "cc -std=c23 -Wno-type-limits ")
        cmd = cmd.replace(" -Werror ", " -Werror -Wno-error=cpp ")
    if tool == "setfacl":
        cmd = cmd.replace(" -Werror ", " -Werror -Wno-error=cpp ")
    if tool == "chio":
        cmd = cmd.replace("cc -std=c23 ", "cc -std=c23 -Wno-sequence-point ")
    if tool == "pax":
        cmd = cmd.replace("cc -std=c23 ", "cc -std=c23 -Wno-implicit-fallthrough ")
        cmd = cmd.replace(" -Werror ", " -Werror -Wno-error=cpp -Wno-overflow ")
    if tool == "sh":
        cmd = cmd.replace(" -Werror ", " -Werror -Wno-error=cpp -Wno-error=unterminated-string-initialization ")
    if tool != "diff3" and tool != "freebsd-version" and tool != "adduser" and " -lfts" not in cmd:
        cmd = cmd + " -lfts"
    return cmd


def write_build_script(tools: list[str]) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    script = OUT / "build-mixtarrvs-musl.sh"
    lines = [
        "#!/usr/bin/env sh",
        "set -eu",
        'ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)',
        'cd "$ROOT"',
        "mkdir -p out/mixtarrvs-musl-target/bin out/mixtarrvs-musl-target/libexec out/mixtarrvs-musl-target/logs",
        'echo "building MixtarRVS musl Toolkit target in $ROOT"',
    ]
    for tool in tools:
        lines.append(f"echo '== {tool} =='")
        command = musl_command(tool)
        lines.append(
            f"({command}) >out/mixtarrvs-musl-target/logs/{tool}.log 2>&1 || "
            f"{{ echo 'FAIL {tool}'; tail -120 out/mixtarrvs-musl-target/logs/{tool}.log; exit 1; }}"
        )
    lines.append("printf '%s\\n' " + " ".join(f"'{tool}'" for tool in tools) + " > out/mixtarrvs-musl-target/TOOLS")
    lines.append("echo done")
    script.write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
    return script


def create_package(tools: list[str]) -> Path:
    script = write_build_script(tools)
    if PACKAGE.exists():
        PACKAGE.unlink()
    members = [
        script,
        REPO / "Server" / "Userland" / "Toolkit" / "FreeBSD" / "freebsd-src" / "bin",
        REPO / "Server" / "Userland" / "Toolkit" / "FreeBSD" / "freebsd-src" / "sbin",
        REPO / "Server" / "Userland" / "Toolkit" / "FreeBSD" / "freebsd-src" / "usr.bin",
        REPO / "Server" / "Userland" / "Toolkit" / "FreeBSD" / "freebsd-src" / "usr.sbin",
        REPO / "Server" / "Userland" / "Toolkit" / "OpenBSD" / "src" / "bin",
        REPO / "Server" / "Userland" / "Toolkit" / "OpenBSD" / "src" / "sbin",
        REPO / "Server" / "Userland" / "Toolkit" / "OpenBSD" / "src" / "usr.bin",
        REPO / "Server" / "Userland" / "Toolkit" / "OpenBSD" / "src" / "usr.sbin",
        REPO / "Server" / "Userland" / "Toolkit" / "OpenBSD" / "src" / "lib",
        REPO / "Server" / "Userland" / "Toolkit" / "Bridge" / "include",
        REPO / "Server" / "Userland" / "Toolkit" / "Bridge" / "scripts",
        REPO / "Server" / "Userland" / "Generated" / "build" / "fdisk",
        REPO / "Server" / "Runtime" / "LibC" / "Generated",
    ]
    with tarfile.open(PACKAGE, "w:gz") as tar:
        for member in members:
            if member.exists():
                tar.add(member, arcname=str(member.relative_to(REPO)))
    return PACKAGE


def remote(remote: str, command: str) -> None:
    run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", remote, command])


def install_mixtar(selection: str, remote_host: str) -> None:
    tools = resolve_tools(selection)
    package = create_package(tools)
    boot_critical = remote_words(BOOT_CRITICAL_TOOLS)
    busybox_applets = remote_words(BOOT_COMPAT_BUSYBOX_APPLETS)
    sbin_busybox_applets = remote_words(BOOT_COMPAT_SBIN_BUSYBOX_APPLETS)
    run(["scp", "-q", str(package), f"{remote_host}:{REMOTE_TARBALL}"])
    remote(
        remote_host,
        "set -eu; "
        "sudo apk add --no-cache build-base linux-headers musl-fts-dev zlib-dev libbsd-dev flex bison ncurses-dev perl gawk >/dev/null; "
        f"rm -rf {REMOTE_BUILD}; mkdir -p {REMOTE_BUILD}; "
        f"tar -xzf {REMOTE_TARBALL} -C {REMOTE_BUILD}; "
        f"cd {REMOTE_BUILD}; sh out/mixtarrvs-musl/build-mixtarrvs-musl.sh; "
        "sudo install -d -m 0755 /System/Tools/MixtarRVS/bin; "
        "sudo install -d -m 0755 /System/Tools/MixtarRVS/libexec; "
        "sudo cp out/mixtarrvs-musl-target/bin/* /System/Tools/MixtarRVS/bin/; "
        "if [ -d out/mixtarrvs-musl-target/libexec ]; then sudo cp out/mixtarrvs-musl-target/libexec/* /System/Tools/MixtarRVS/libexec/ 2>/dev/null || true; fi; "
        "sudo chmod 0755 /System/Tools/MixtarRVS/bin/*; "
        "if [ -d /System/Tools/MixtarRVS/libexec ]; then sudo chmod 0755 /System/Tools/MixtarRVS/libexec/* 2>/dev/null || true; fi; "
        "sudo install -d -m 0755 /System/Logs; "
        "sudo install -d -m 0755 /System/Runtime/run; "
        "if [ -L /run ]; then sudo rm -f /run; fi; "
        "sudo install -d -m 0755 /run; "
        "stamp=$(date +%Y%m%d-%H%M%S); "
        "sudo install -d -m 0755 /System/Logs/toolkit-install-guard-$stamp; "
        f"if [ -L {BOOT_COMPAT_ROOT}/bin ]; then sudo rm -f {BOOT_COMPAT_ROOT}/bin; fi; "
        f"if [ -L {BOOT_COMPAT_ROOT}/sbin ]; then sudo rm -f {BOOT_COMPAT_ROOT}/sbin; fi; "
        f"sudo install -d -m 0755 {BOOT_COMPAT_ROOT}/bin {BOOT_COMPAT_ROOT}/sbin; "
        f"for tool in {boot_critical}; do "
        "  p=/System/Tools/MixtarRVS/bin/$tool; "
        "  b=/System/Tools/MixtarRVS/bin/bsd-$tool; "
        "  if [ -e $p ] && [ ! -L $p ]; then "
        "    if [ -e $b ]; then sudo mv $p /System/Logs/toolkit-install-guard-$stamp/$tool; "
        "    else sudo mv $p $b; fi; "
        "  fi; "
        "done; "
        "sudo ln -sfn /bin/busybox /System/Tools/MixtarRVS/bin/sh; "
        f"for app in {busybox_applets}; do "
        f"  p={BOOT_COMPAT_ROOT}/bin/$app; "
        "  if [ -e $p ] && [ ! -L $p ]; then sudo mv $p /System/Logs/toolkit-install-guard-$stamp/$app.compat-previous; fi; "
        "  sudo ln -sfn /bin/busybox $p; "
        "done; "
        f"for app in {sbin_busybox_applets}; do "
        f"  p={BOOT_COMPAT_ROOT}/sbin/$app; "
        "  if [ -e $p ] && [ ! -L $p ]; then sudo mv $p /System/Logs/toolkit-install-guard-$stamp/$app.compat-previous; fi; "
        "  sudo ln -sfn /bin/busybox $p; "
        "done; "
        "bin_link=$(readlink /bin 2>/dev/null || true); "
        "sbin_link=$(readlink /sbin 2>/dev/null || true); "
        "case $bin_link in /System/Tools/Current/bin|System/Tools/Current/bin) echo 'refusing unsafe /bin -> /System/Tools/Current/bin' >&2; exit 1;; esac; "
        "case $sbin_link in /System/SystemTools|System/SystemTools) echo 'refusing unsafe /sbin -> /System/SystemTools' >&2; exit 1;; esac; "
        f"if [ -L /bin ]; then sudo ln -sfn {BOOT_COMPAT_ROOT[1:]}/bin /bin; fi; "
        f"if [ -L /sbin ]; then sudo ln -sfn {BOOT_COMPAT_ROOT[1:]}/sbin /sbin; fi; "
        "sudo ln -sfn MixtarRVS /System/Tools/Current; "
        "printf '%s\\n' 'MixtarRVS musl userland profile' "
        "'Installed via toolkit_build install-mixtar' "
        "'Install path: /System/Tools/MixtarRVS/bin' "
        "'Current alias: /System/Tools/Current -> MixtarRVS' "
        "'Runtime: Alpine/musl, interpreter /lib/ld-musl-x86_64.so.1' "
        "'Boot closure: /bin and /sbin remain Alpine/BusyBox compatibility until Mixtar owns init/mount/service/network closure' "
        "'Guarded names moved to bsd-* when the BSD source command is not safe as a Linux boot/runtime primitive' "
        f"'Group: {selection}' "
        f"'Tools: {' '.join(tools)}' | sudo tee /System/Tools/MixtarRVS/manifest.txt >/dev/null",
    )


def compat_alpine(remote_host: str) -> None:
    remote(
        remote_host,
        "set -eu; "
        "sudo install -d -m 0755 /Compatibility/POSIX/Alpine/3.24/bin /Compatibility/POSIX/Alpine/3.24/sbin; "
        "for p in lib usr etc var opt media mnt srv root run tmp home dev proc sys; do "
        "  sudo ln -sfn /$p /Compatibility/POSIX/Alpine/3.24/$p; "
        "done; "
        "sudo install -d -m 0755 /System/Config/MixtarRVS; "
        "printf '%s\\n' 'Alpine compatibility backend' "
        "'Path: /Compatibility/POSIX/Alpine/3.24' "
        "'Mode: symlink view only; no system directories moved' "
        "'Purpose: keep Alpine/OpenRC/apk/bootstrap visible as compatibility substrate' "
        "| sudo tee /Compatibility/POSIX/Alpine/3.24/README.txt >/dev/null",
    )


def clean_root_profile(remote_host: str) -> None:
    remote(
        remote_host,
        "set -eu; "
        "sudo install -d -m 0755 /System/Runtime/Profiles/clean-root-next; "
        "printf '%s\\n' 'MixtarRVS clean-root runtime namespace profile' "
        "'Status: prepared, not boot-active' "
        "'Goal: / shows Applications Compatibility Programs System Temporary Users Volumes' "
        "'POSIX backend: /Compatibility/POSIX/Alpine/3.24' "
        "'Mount strategy: future initramfs/private namespace bind mounts only' "
        "'Safety: do not move /bin /sbin /etc /usr /lib /var; OpenRC and boot flow unchanged' "
        "| sudo tee /System/Runtime/Profiles/clean-root-next/profile.txt >/dev/null; "
        "printf '%s\\n' '#!/bin/sh' 'set -eu' "
        "'echo clean-root-next is a prepared profile, not an active boot profile' "
        "'echo use existing mixtar-clean-root-view for private namespace preview if available' "
        "| sudo tee /System/Runtime/Profiles/clean-root-next/enter-preview.sh >/dev/null; "
        "sudo chmod 0755 /System/Runtime/Profiles/clean-root-next/enter-preview.sh",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["package", "install", "compat-alpine", "clean-root-profile"])
    parser.add_argument("selection", nargs="?", default="minimum")
    parser.add_argument("--remote", default=REMOTE_DEFAULT)
    args = parser.parse_args()

    if args.action == "package":
        package = create_package(resolve_tools(args.selection))
        print(package)
        return 0
    if args.action == "install":
        install_mixtar(args.selection, args.remote)
        return 0
    if args.action == "compat-alpine":
        compat_alpine(args.remote)
        return 0
    if args.action == "clean-root-profile":
        clean_root_profile(args.remote)
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
