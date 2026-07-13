#!/System/Shells/zsh.apx/Program/zsh
set -eu

if (( $# != 3 )); then
    print -u2 -- "usage: build_zsh_musl.sh ZSH_ARCHIVE NCURSES_ARCHIVE WORK_DIR"
    exit 64
fi

zsh_archive=$1
ncurses_archive=$2
work_dir=$3
build_root=$work_dir/build
stage=$work_dir/stage
ncurses_root=$work_dir/ncurses-root
ncurses_src=$build_root/ncurses
zsh_src=$build_root/zsh
bundle=$stage/System/Shells/zsh.apx
terminfo_root=$bundle/Resources/Terminfo
archive=/System/Compilers/BSDTar/3.8.8/bin/bsdtar
gmake=/System/Compilers/GNU/4.4.1/bin/gmake
export MAKE=$gmake

if [[ -z ${MIXTAR_TOOLCHAIN:-} || -z ${CC:-} || -z ${AR:-} || -z ${RANLIB:-} || -z ${LD:-} ]]; then
    print -u2 -- "build-zsh-musl: toolchain environment is incomplete"
    exit 69
fi

for required in \
    $MIXTAR_TOOLCHAIN \
    $archive \
    $gmake \
    /System/Userland/chmod \
    /System/Userland/cp \
    /System/Userland/mkdir \
    /System/Userland/rm \
    /System/Userland/sed
do
    if [[ ! -x $required ]]; then
        print -u2 -- "build-zsh-musl: missing required tool: $required"
        exit 69
    fi
done

if [[ ! -f $zsh_archive || ! -f $ncurses_archive ]]; then
    print -u2 -- "build-zsh-musl: verified source archive is missing"
    exit 66
fi

case $work_dir in
    /Temporary/Updates/Work/*) ;;
    *)
        print -u2 -- "build-zsh-musl: work directory is outside the isolated workspace"
        exit 73
        ;;
esac

/System/Userland/rm -rf -- "$build_root" "$stage" "$ncurses_root"
/System/Userland/mkdir -p -- "$ncurses_src" "$zsh_src" "$stage" "$ncurses_root"
$archive -xf "$ncurses_archive" -C "$ncurses_src" --strip-components 1
$archive -xf "$zsh_archive" -C "$zsh_src" --strip-components 1

cd "$ncurses_src"
CC="$CC" AR="$AR" RANLIB="$RANLIB" LD="$LD" \
CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra' \
LDFLAGS='-static' \
CONFIG_SHELL=/bin/sh SHELL=/bin/sh \
./configure \
    --prefix=/System/Shells/zsh.apx/Resources/Ncurses \
    --with-terminfo-dirs=/System/Shells/zsh.apx/Resources/Terminfo \
    --with-default-terminfo-dir=/System/Shells/zsh.apx/Resources/Terminfo \
    --without-shared --with-normal --without-debug --without-cxx \
    --without-cxx-binding --without-form --without-menu --without-panel \
    --enable-widec --without-ada --without-manpages --without-tests \
    --disable-stripping
$gmake -j2 SHELL=/bin/sh CONFIG_SHELL=/bin/sh \
    LIBS_TIC='-L../lib -static -lncursesw' \
    LIBS_TINFO='-static -lncursesw'
export PATH=$build_root/ncurses/progs:$PATH
$gmake install DESTDIR="$ncurses_root" \
    LIBS_TIC='-L../lib -static -lncursesw' \
    LIBS_TINFO='-static -lncursesw'

ncurses_prefix=$ncurses_root/System/Shells/zsh.apx/Resources/Ncurses
cd "$zsh_src"
for source_file in Src/init.c Src/exec.c Src/Zle/zle_main.c Src/Modules/watch.c; do
    /System/Userland/sed -i \
        's#/dev/null#/System/Devices/null#g' \
        "$source_file"
done
CC="$CC" AR="$AR" RANLIB="$RANLIB" LD="$LD" \
CFLAGS='-O3 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra' \
CPPFLAGS="-I$ncurses_prefix/include" \
LDFLAGS="-static -L$ncurses_prefix/lib" \
LIBS='-lncursesw' \
CONFIG_SHELL=/bin/sh SHELL=/bin/sh \
./configure \
    --build=x86_64-mixtarrvs-linux-musl \
    --host=x86_64-mixtarrvs-linux-musl \
    --prefix=/System/Shells/zsh.apx \
    --bindir=/System/Shells/zsh.apx/Program \
    --libdir=/System/Shells/zsh.apx/Resources/Modules \
    --datadir=/System/Shells/zsh.apx/Resources/Share \
    --mandir=/System/Shells/zsh.apx/Resources/Documentation/man \
    --infodir=/System/Shells/zsh.apx/Resources/Documentation/info \
    --enable-fndir=/System/Shells/zsh.apx/Resources/Functions \
    --disable-dynamic --disable-dynamic-nss --enable-multibyte \
    --enable-etcdir=/System/Shells/zsh.apx/Resources/Configuration \
    --enable-zshenv=/System/Shells/zsh.apx/Resources/Configuration/.zshenv
$gmake -j2 SHELL=/bin/sh CONFIG_SHELL=/bin/sh
$gmake install DESTDIR="$stage"

/System/Userland/mkdir -p -- "$terminfo_root"
if [[ -d $ncurses_root/System/Shells/zsh.apx/Resources/Terminfo ]]; then
    /System/Userland/cp -Rp -- \
        "$ncurses_root/System/Shells/zsh.apx/Resources/Terminfo/." \
        "$terminfo_root/"
fi

zsh_binary=$bundle/Program/zsh
if [[ ! -x $zsh_binary ]]; then
    print -u2 -- "build-zsh-musl: ZSH artifact was not produced"
    exit 70
fi
TERMINFO="$terminfo_root" "$zsh_binary" --version >$work_dir/zsh-version.txt
/System/Userland/chmod 0755 "$zsh_binary"

print -- "build-zsh-musl: PASS"
print -- "artifact=$zsh_binary"
/System/Userland/cat "$work_dir/zsh-version.txt"
