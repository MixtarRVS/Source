#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
    echo "usage: build_ailang_updaters_musl.sh REPO_ROOT AILANG_ROOT SQLITE_PREFIX OUTPUT_DIR" >&2
    exit 64
fi

repo_root=$(realpath "$1")
ailang_root=$(realpath "$2")
sqlite_prefix=$(realpath "$3")
output_dir=$(realpath -m "$4")
temporary_dir="$output_dir.tmp.$$"
python=${PYTHON:-python3}
compiler=${CC:-musl-gcc}
build_timeout=${MIXTAR_BUILD_TIMEOUT:-90}
sha256_recipe="$repo_root/Server/Updates/Recipes/build_sha256_musl.sh"
sha256_source="$repo_root/Server/Userland/Toolkit/OpenBSD/src"
sha256_zig=${MIXTAR_ZIG:-"$repo_root/out/server/corev09-inputs/Compilers/Zig/0.16.0/zig"}
sha256_work="$output_dir.sha256.tmp.$$"

case "$output_dir" in
    "$repo_root"/out/server/*|/Temporary/Updates/Work/*) ;;
    *)
        echo "build-updaters: output must remain in Mixtar build workspace" >&2
        exit 73
        ;;
esac

for required in \
    "$ailang_root/ailang.py" \
    "$sqlite_prefix/include/sqlite3.h" \
    "$sqlite_prefix/lib/libsqlite3.a" \
    "$sha256_recipe" \
    "$sha256_source/lib/libc/hash/sha2.c" \
    "$sha256_source/include/sha2.h"
do
    [ -f "$required" ] || {
        echo "build-updaters: missing input: $required" >&2
        exit 66
    }
done
[ -x "$sha256_zig" ] || {
    echo "build-updaters: missing Zig toolchain: $sha256_zig" >&2
    exit 66
}

command -v "$python" >/dev/null 2>&1 || {
    echo "build-updaters: Python interpreter is unavailable" >&2
    exit 69
}
command -v "$compiler" >/dev/null 2>&1 || {
    echo "build-updaters: musl compiler is unavailable" >&2
    exit 69
}
command -v timeout >/dev/null 2>&1 || {
    echo "build-updaters: timeout utility is unavailable" >&2
    exit 69
}

case "$temporary_dir" in
    "$output_dir".tmp.*) rm -rf -- "$temporary_dir" ;;
    *) exit 73 ;;
esac
mkdir -p "$temporary_dir"

cleanup() {
    case "$temporary_dir" in
        "$output_dir".tmp.*) rm -rf -- "$temporary_dir" ;;
    esac
    case "$sha256_work" in
        "$output_dir".sha256.tmp.*) rm -rf -- "$sha256_work" ;;
    esac
}
trap cleanup EXIT INT TERM

build_one() {
    output_name=$1
    generated_stem=$2
    source_name=$3
    source_path="$repo_root/Server/Updates/$source_name"

    [ -f "$source_path" ] || {
        echo "build-updaters: missing AILang source: $source_path" >&2
        exit 66
    }
    echo "build-updaters: $output_name"
    timeout "${build_timeout}s" "$python" "$ailang_root/ailang.py" \
        "$source_path" --backend=c -o "$temporary_dir/$output_name.backend"
    generated_c=$(find "$ailang_root/out/generated/c_backend" -maxdepth 1 -type f \
        -name "${generated_stem}_*.c" -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
    [ -f "$generated_c" ] || {
        echo "build-updaters: generated C is missing for $source_name" >&2
        exit 70
    }
    rm -f -- "$temporary_dir/$output_name.backend"
    timeout "${build_timeout}s" "$compiler" \
        -std=c23 -O3 -Wall -Wextra -Werror -pedantic \
        -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 -static \
        -I"$sqlite_prefix/include" "$generated_c" \
        "$sqlite_prefix/lib/libsqlite3.a" -lm -lpthread \
        -o "$temporary_dir/$output_name"
    file "$temporary_dir/$output_name" | grep -F 'statically linked' >/dev/null || {
        echo "build-updaters: non-static output: $output_name" >&2
        exit 70
    }
}

while IFS='|' read -r output_name generated_stem source_name; do
    [ -n "$output_name" ] || continue
    build_one "$output_name" "$generated_stem" "$source_name"
done <<'EOF'
updates|updates|updates.ail
updates-config-builder|updates_config_builder|updates_config_builder.ail
updates-grml|updates_grml|updates_grml.ail
updates-kernel|updates_kernel|updates_kernel.ail
updates-kernel-config|updates_kernel_config|updates_kernel_config.ail
updates-kernel-prepare|updates_kernel_prepare|updates_kernel_prepare.ail
updates-kernel-source|updates_kernel_source|updates_kernel_source.ail
updates-kernel-stage|updates_kernel_stage|updates_kernel_stage.ail
updates-mixtar|updates_mixtar|updates_mixtar.ail
updates-ncurses|updates_ncurses|updates_ncurses.ail
updates-openbsd|updates_openbsd|updates_openbsd.ail
updates-signature-verify|updates_signature_verify|updates_signature_verify.ail
updates-zsh-build|updates_zsh_build|updates_zsh_build.ail
mixtar-build-executor|updates_build_executor|updates_build_executor.ail
EOF

case "$sha256_work" in
    "$output_dir".sha256.tmp.*) rm -rf -- "$sha256_work" ;;
    *) exit 73 ;;
esac
"$sha256_recipe" "$sha256_zig" "$sha256_source" "$sha256_work"
install -m 0755 \
    "$sha256_work/stage/System/Userland/mixtar-sha256" \
    "$temporary_dir/mixtar-sha256"
rm -rf -- "$sha256_work"

count=$(find "$temporary_dir" -maxdepth 1 -type f -perm -0100 | wc -l)
[ "$count" -eq 15 ] || {
    echo "build-updaters: expected 15 executables, found $count" >&2
    exit 70
}

config="$temporary_dir/Updates.config"
"$temporary_dir/updates-config-builder" build \
    "$repo_root/Server/Updates/Schema/Updates.schema.sql" \
    "$repo_root/Server/Updates/Schema/Updates.seed.sql" \
    "$config"
"$temporary_dir/updates" audit "$config"
rm -f -- "$config"

rm -rf -- "$output_dir"
mv "$temporary_dir" "$output_dir"
trap - EXIT INT TERM
echo "UPDATES_MUSL_STATIC_COUNT=$count"
echo "UPDATES_MUSL_STATIC_GATE=PASS"
