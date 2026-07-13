#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"

default_kernel_src="${HOME:-/tmp}/.cache/mixtarrvs-corev05/kernel/src/linux-7.1.2"
kernel_src="${1:-${KERNEL_SRC:-$default_kernel_src}}"

fail() {
  echo "mixtar-kernel-patch: error: $*" >&2
  exit 1
}

[[ -f "$kernel_src/Makefile" ]] || fail "kernel source missing: $kernel_src"

python3 - "$kernel_src" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

def patch_file(rel: str, replacements: list[tuple[str, str]]) -> None:
    path = root / rel
    text = path.read_text(encoding="utf-8", errors="replace")
    original = text
    for old, new in replacements:
        if old in text:
            text = text.replace(old, new, 1)
        elif new in text:
            pass
        else:
            raise SystemExit(f"pattern not found in {rel}: {old[:80]!r}")
    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"patched {rel}")
    else:
        print(f"already patched {rel}")

patch_file(
    "init/main.c",
    [
        (
            'if (!try_to_run_init_process("/sbin/init") ||\n'
            '\t    !try_to_run_init_process("/etc/init") ||\n'
            '\t    !try_to_run_init_process("/bin/init") ||\n'
            '\t    !try_to_run_init_process("/bin/sh"))\n'
            '\t\treturn 0;\n\n'
            '\tpanic("No working init found.  Try passing init= option to kernel. "\n'
            '\t      "See Linux Documentation/admin-guide/init.rst for guidance.");',
            'if (!try_to_run_init_process("/System/Init/MixtarRVS"))\n'
            '\t\treturn 0;\n\n'
            '\tpanic("No working MixtarRVS init found at /System/Init/MixtarRVS. "\n'
            '\t      "Pass init= or rdinit= with a Mixtar-compatible init path.");',
        ),
        (
            '/* Open /dev/console, for stdin/stdout/stderr, this should never fail */',
            '/* Open the Mixtar console for stdin/stdout/stderr, this should never fail */',
        ),
        (
            'struct file *file = filp_open("/dev/console", O_RDWR, 0);',
            'struct file *file = filp_open("/System/Devices/console", O_RDWR, 0);',
        ),
    ],
)

patch_file(
    "init/do_mounts.c",
    [
        (
            'int err = create_dev("/dev/root", ROOT_DEV);',
            'int err = create_dev("/System/Devices/root", ROOT_DEV);',
        ),
        (
            'pr_emerg("Failed to create /dev/root: %d\\n", err);',
            'pr_emerg("Failed to create /System/Devices/root: %d\\n", err);',
        ),
        (
            'mount_root_generic("/dev/root", root_device_name, root_mountflags);',
            'mount_root_generic("/System/Devices/root", root_device_name, root_mountflags);',
        ),
    ],
)

patch_file(
    "init/noinitramfs.c",
    [
        (
            '\tusermodehelper_enable();\n'
            '\terr = init_mkdir("/dev", 0755);\n'
            '\tif (err < 0)\n'
            '\t\tgoto out;\n\n'
            '\terr = init_mknod("/dev/console", S_IFCHR | S_IRUSR | S_IWUSR,\n'
            '\t\t\tnew_encode_dev(MKDEV(5, 1)));\n'
            '\tif (err < 0)\n'
            '\t\tgoto out;\n\n'
            '\terr = init_mkdir("/root", 0700);\n'
            '\tif (err < 0)\n'
            '\t\tgoto out;',
            '\tusermodehelper_enable();\n'
            '\terr = init_mkdir("/System", 0755);\n'
            '\tif (err < 0)\n'
            '\t\tgoto out;\n\n'
            '\terr = init_mkdir("/System/Devices", 0755);\n'
            '\tif (err < 0)\n'
            '\t\tgoto out;\n\n'
            '\terr = init_mknod("/System/Devices/console", S_IFCHR | S_IRUSR | S_IWUSR,\n'
            '\t\t\tnew_encode_dev(MKDEV(5, 1)));\n'
            '\tif (err < 0)\n'
            '\t\tgoto out;\n\n'
            '\terr = init_mkdir("/Users", 0755);\n'
            '\tif (err < 0)\n'
            '\t\tgoto out;\n\n'
            '\terr = init_mkdir("/Users/root", 0700);\n'
            '\tif (err < 0)\n'
            '\t\tgoto out;',
        )
    ],
)
PY

echo "mixtar-kernel-patch: source ready: $kernel_src"
