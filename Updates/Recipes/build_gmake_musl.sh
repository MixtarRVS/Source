#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_gmake_musl.sh SOURCE_DIR WORK_DIR OUTPUT_DIR"
    exit 64
fi

source_dir=$1
work_dir=$2
output_dir=$3
source_copy=$work_dir/source
build_dir=$work_dir/build
stage_dir=$work_dir/stage

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-gmake-musl: toolchain environment is incomplete"
    exit 69
fi

for required in \
    /System/Compilers/GNU/4.4.1/bin/gmake \
    $MIXTAR_TOOLCHAIN \
    /System/Userland/cp \
    /System/Userland/chmod \
    /System/Userland/mkdir \
    /System/Userland/rm
do
    if [[ ! -x $required ]]; then
        print -u2 -- "build-gmake-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -f $source_dir/configure || ! -f $source_dir/Makefile.in ]]; then
    print -u2 -- "build-gmake-musl: invalid GNU Make source tree: $source_dir"
    exit 66
fi

case $work_dir in
    /Temporary/Work/*) ;;
    *)
        print -u2 -- "build-gmake-musl: work directory is outside the update workspace"
        exit 73
        ;;
esac

/System/Userland/rm -rf -- "$source_copy" "$build_dir" "$stage_dir"
/System/Userland/mkdir -p -- "$source_copy" "$build_dir" "$stage_dir" "$output_dir"
/System/Userland/cp -Rp -- "$source_dir/." "$source_copy/"

cd "$build_dir"

CC="$CC" \
AR="$AR" \
RANLIB="$RANLIB" \
LD="$LD" \
MAKE='/System/Compilers/GNU/4.4.1/bin/gmake' \
CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Werror -Wno-error=string-compare -Wno-error=incompatible-library-redeclaration -Wno-error=deprecated-non-prototype' \
LDFLAGS='-static' \
CONFIG_SHELL=/bin/sh \
SHELL=/bin/sh \
"$source_copy/configure" \
    --prefix=/System/Userland \
    --disable-dependency-tracking \
    --disable-nls \
    --without-guile

/System/Compilers/GNU/4.4.1/bin/gmake -j2 SHELL=/bin/sh CONFIG_SHELL=/bin/sh

candidate=$build_dir/make
if [[ ! -x $candidate ]]; then
    print -u2 -- "build-gmake-musl: expected output was not produced"
    exit 70
fi

/System/Userland/cp -- "$candidate" "$output_dir/gmake"
/System/Userland/chmod 0755 "$output_dir/gmake"

"$output_dir/gmake" --version >/Temporary/Work/gmake-version.txt
print -- "build-gmake-musl: PASS"

