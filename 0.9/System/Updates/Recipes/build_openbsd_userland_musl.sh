#!/System/Shells/zsh.apx/Program/zsh
set -eu
setopt null_glob

if (( $# != 16 )); then
    print -u2 -- "usage: build_openbsd_userland_musl.sh OPENBSD_SRC MIXTAR_SRC NCURSES_SRC WORK PLAN FTS_PATCH COUNT ARCHIVE MAKE PATCH CP MKDIR RM FIND WC ZLIB"
    exit 64
fi

openbsd_archive=$1
mixtar_archive=$2
ncurses_archive=$3
work=$4
plan=$5
fts_patch=$6
expected_count=$7
archive=$8
make_tool=$9
patch_tool=${10}
cp_tool=${11}
mkdir_tool=${12}
rm_tool=${13}
find_tool=${14}
wc_tool=${15}
zlib_prefix=${16}
build=$work/build
stage=$work/stage
source_parent=$build/source
ncurses_source=$build/ncurses
ncurses_prefix=$build/deps/ncurses
fts_root=$build/deps/fts
logs=$work/logs
output=$stage/System/Userland

case $work in
    /Temporary/Updates/Work/*) ;;
    *) print -u2 -- "openbsd-userland-build: unsafe work path"; exit 73 ;;
esac

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} ]]; then
    print -u2 -- "openbsd-userland-build: toolchain environment is incomplete"
    exit 69
fi
for required in $openbsd_archive $mixtar_archive $ncurses_archive $plan $fts_patch; do
    [[ -f $required ]] || { print -u2 -- "openbsd-userland-build: missing input $required"; exit 66; }
done
for required in $MIXTAR_TOOLCHAIN $archive $make_tool $patch_tool $cp_tool $mkdir_tool $rm_tool $find_tool $wc_tool; do
    [[ -x $required ]] || { print -u2 -- "openbsd-userland-build: missing tool $required"; exit 69; }
done
for required in $zlib_prefix/include/zlib.h $zlib_prefix/lib/libz.a; do
    [[ -f $required ]] || { print -u2 -- "openbsd-userland-build: missing zlib sysroot $required"; exit 69; }
done

$rm_tool -rf -- $build $stage $logs
$mkdir_tool -p -- $source_parent $ncurses_source $ncurses_prefix $fts_root/include $fts_root/lib $logs $output
$archive -xf $mixtar_archive -C $source_parent
repos=($source_parent/MixtarRVS-*(/N))
if (( ${#repos} != 1 )); then
    print -u2 -- "openbsd-userland-build: signed Mixtar source has an invalid root"
    exit 66
fi
repo=$repos[1]
openbsd_root=$repo/Server/Userland/Toolkit/OpenBSD/src
$rm_tool -rf -- $openbsd_root
$mkdir_tool -p -- $openbsd_root
$archive -xf $openbsd_archive -C $openbsd_root
$archive -xf $ncurses_archive -C $ncurses_source --strip-components 1

cd $ncurses_source
CC="$CC" AR="$AR" RANLIB="$RANLIB" LD="$LD" \
CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra' \
LDFLAGS='-static' CONFIG_SHELL=/bin/sh SHELL=/bin/sh \
./configure --prefix=$ncurses_prefix --without-shared --with-normal \
    --without-debug --without-cxx --without-cxx-binding --without-form \
    --without-menu --without-panel --enable-widec --with-termlib \
    --without-ada --without-manpages --without-tests --disable-stripping
$make_tool -j2 SHELL=/bin/sh CONFIG_SHELL=/bin/sh \
    LIBS_TIC='-L../lib -static -lncursesw -ltinfo' \
    LIBS_TINFO='-static -lncursesw'
$make_tool install SHELL=/bin/sh CONFIG_SHELL=/bin/sh

$cp_tool $openbsd_root/lib/libc/gen/fts.c $fts_root/fts.c
$cp_tool $openbsd_root/include/fts.h $fts_root/include/fts.h
$patch_tool -d $fts_root -p0 < $fts_patch
$MIXTAR_TOOLCHAIN cc -target x86_64-linux-musl -static -O3 \
    -D_GNU_SOURCE -D_DEFAULT_SOURCE -I$repo/Server/Userland/Toolkit/Bridge/include \
    -I$fts_root/include -c $fts_root/fts.c -o $fts_root/fts.o
$MIXTAR_TOOLCHAIN ar rcs $fts_root/lib/libfts.a $fts_root/fts.o
print 'void mixtar_libutil_archive_anchor(void) {}' > $fts_root/util.c
$MIXTAR_TOOLCHAIN cc -target x86_64-linux-musl -static -O3 \
    -c $fts_root/util.c -o $fts_root/util.o
$MIXTAR_TOOLCHAIN ar rcs $fts_root/lib/libutil.a $fts_root/util.o

mixtar_cc() {
    $MIXTAR_TOOLCHAIN cc -target x86_64-linux-musl -static \
        -I$fts_root/include -I$ncurses_prefix/include \
        -I$ncurses_prefix/include/ncursesw -I$zlib_prefix/include \
        -L$fts_root/lib -L$ncurses_prefix/lib -L$zlib_prefix/lib "$@"
}

export MIXTAR_SOURCE_ROOT=$repo
export MIXTAR_USERLAND_OUTPUT=$output
export MIXTAR_USERLAND_LOGS=$logs
cd $repo
source $plan

actual_count=$($find_tool $output -maxdepth 1 -type f -perm -0100 | $wc_tool -l)
actual_count=${actual_count//[[:space:]]/}
if [[ $actual_count != $expected_count ]]; then
    print -u2 -- "openbsd-userland-build: expected $expected_count executables, got $actual_count"
    exit 70
fi
{
    print -- "schema=mixtar.userland.candidate.v1"
    print -- "openbsd_source=${openbsd_archive:t}"
    print -- "mixtar_source=${mixtar_archive:t}"
    print -- "tool_count=$actual_count"
    print -- "activation=forbidden-before-full-verifier"
} > $output/BUILD-MANIFEST
print -- "openbsd-userland-build: PASS"
print -- "candidate=$output"
print -- "tool_count=$actual_count"
