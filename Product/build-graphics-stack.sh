#!/usr/bin/env bash
set -Eeuo pipefail

: "${MIXTAR_REPOSITORY:?MIXTAR_REPOSITORY is required}"
: "${MIXTAR_OUTPUT:?MIXTAR_OUTPUT is required}"
: "${MIXTAR_STACK_KEY:?MIXTAR_STACK_KEY is required}"
: "${MIXTAR_SOURCE_DATE_EPOCH:?MIXTAR_SOURCE_DATE_EPOCH is required}"
: "${MIXTAR_JOBS:?MIXTAR_JOBS is required}"

readonly repository="$(realpath -m -- "${MIXTAR_REPOSITORY}")"
readonly output="$(realpath -m -- "${MIXTAR_OUTPUT}")"
readonly cache_root="$(realpath -m -- "${XDG_CACHE_HOME:-${HOME}/.cache}/mixtar/graphics")"
readonly archive_root="${cache_root}/archives"
readonly source_root="${cache_root}/sources"
readonly build_root="${cache_root}/build/${MIXTAR_STACK_KEY}"
readonly sysroot="${cache_root}/stage/${MIXTAR_STACK_KEY}"
readonly complete_marker="${sysroot}/.mixtar-graphics-complete"
readonly library_prefix="/System/Libraries/Graphics"

case "${output}" in
    "${repository}"/out/*) ;;
    *)
        printf 'Refusing graphics output outside repository out/: %s\n' "${output}" >&2
        exit 2
        ;;
esac

case "${cache_root}" in
    /|/home|/home/*/.cache)
        printf 'Refusing unsafe graphics cache root: %s\n' "${cache_root}" >&2
        exit 2
        ;;
esac

component_value() {
    local id="${1^^}"
    local field="${2^^}"
    id="${id//-/_}"
    local variable="MIXTAR_${id}_${field}"
    local value="${!variable:-}"
    if [[ -z "${value}" ]]; then
        printf 'Missing component value: %s\n' "${variable}" >&2
        exit 2
    fi
    printf '%s' "${value}"
}

component_value_optional() {
    local id="${1^^}"
    local field="${2^^}"
    id="${id//-/_}"
    local variable="MIXTAR_${id}_${field}"
    printf '%s' "${!variable:-}"
}

ensure_archive() {
    local id="$1"
    local archive url expected
    archive="$(component_value "${id}" archive)"
    url="$(component_value "${id}" url)"
    expected="$(component_value "${id}" sha256)"
    mkdir -p "${archive_root}"
    if [[ ! -f "${archive_root}/${archive}" ]]; then
        curl -sS -L --fail --retry 3 -o "${archive_root}/${archive}" "${url}"
    fi
    printf '%s  %s\n' "${expected}" "${archive_root}/${archive}" | sha256sum -c - >/dev/null
}

prepare_source() {
    local id="$1"
    local version archive expected destination marker suffix patch_relative patch_expected
    version="$(component_value "${id}" version)"
    archive="$(component_value "${id}" archive)"
    expected="$(component_value "${id}" sha256)"
    patch_relative="$(component_value_optional "${id}" patch)"
    patch_expected="$(component_value_optional "${id}" patch_sha256)"
    suffix="${expected:0:8}"
    if [[ -n "${patch_relative}" ]]; then
        if [[ -z "${patch_expected}" || ! -f "${repository}/${patch_relative}" ]]; then
            printf 'Missing or unverifiable source patch for %s\n' "${id}" >&2
            exit 2
        fi
        printf '%s  %s\n' "${patch_expected}" "${repository}/${patch_relative}" | sha256sum -c - >/dev/null
        suffix="${suffix}-${patch_expected:0:8}"
    fi
    destination="${source_root}/${id}-${version}-${suffix}"
    marker="${destination}/.mixtar-source-${suffix}"
    ensure_archive "${id}"
    if [[ ! -f "${marker}" ]]; then
        rm -rf -- "${destination}"
        mkdir -p "${destination}"
        tar -xf "${archive_root}/${archive}" --strip-components=1 -C "${destination}"
        if [[ -n "${patch_relative}" ]]; then
            patch -p1 -d "${destination}" -i "${repository}/${patch_relative}" >/dev/null
        fi
        touch -d "@${MIXTAR_SOURCE_DATE_EPOCH}" "${marker}"
    fi
    printf '%s' "${destination}"
}

meson_install() {
    local name="$1"
    local source="$2"
    shift 2
    meson setup "${build_root}/${name}" "${source}" \
        --buildtype=release \
        --prefix=/System \
        --libdir=Libraries/Graphics \
        --includedir=Development/Headers \
        --datadir=Share \
        --wrap-mode=nodownload \
        -Db_ndebug=true \
        -Dstrip=true \
        "$@"
    meson compile -C "${build_root}/${name}" -j "${MIXTAR_JOBS}"
    DESTDIR="${sysroot}" meson install -C "${build_root}/${name}"
}

copy_license() {
    local source="$1"
    local target="$2"
    shift 2
    local candidate
    for candidate in "$@"; do
        if [[ -f "${source}/${candidate}" ]]; then
            mkdir -p "${sysroot}/System/Licenses/Graphics"
            cp "${source}/${candidate}" "${sysroot}/System/Licenses/Graphics/${target}"
            return
        fi
    done
    printf 'No license file found for %s.\n' "${target}" >&2
    exit 3
}

collect_libdrm_licenses() {
    local source="$1"
    local target="${sysroot}/System/Licenses/Graphics/Libdrm.txt"

    mkdir -p "$(dirname "${target}")"
    python3 - "${source}" "${target}" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
notices = set()

for path in sorted(item for item in source.rglob("*") if item.is_file()):
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        continue

    for comment in re.findall(r"/\*.*?\*/", text, flags=re.DOTALL):
        if "Permission is hereby granted" not in comment:
            continue

        body = re.sub(r"^/\*+", "", comment)
        body = re.sub(r"\*/$", "", body)
        lines = []
        for line in body.splitlines():
            lines.append(re.sub(r"^\s*\* ?", "", line).rstrip())
        notice = "\n".join(lines).strip()
        if notice:
            notices.add(notice)

if not notices:
    raise SystemExit("No MIT license notices found in libdrm sources.")

separator = "\n\n" + ("-" * 72) + "\n\n"
with target.open("w", encoding="utf-8", newline="\n") as output:
    output.write("libdrm license notices extracted from the locked source archive.\n\n")
    output.write(separator.join(sorted(notices)))
    output.write("\n")
PY
}

copy_runtime_library() {
    local compiler="$1"
    local name="$2"
    local source
    source="$(${compiler} -print-file-name="${name}")"
    if [[ "${source}" == "${name}" || ! -f "${source}" ]]; then
        return
    fi
    mkdir -p "${sysroot}${library_prefix}"
    cp -L "${source}" "${sysroot}${library_prefix}/${name}"
}

for id in expat libffi wayland wayland-protocols freetype harfbuzz fontconfig libdrm mesa noto-sans noto-sans-mono; do
    ensure_archive "${id}"
done

if [[ ! -f "${complete_marker}" ]]; then
    rm -rf -- "${build_root}" "${sysroot}"
    mkdir -p "${build_root}" "${sysroot}"
    build_started="$(date +%s)"

    expat_source="$(prepare_source expat)"
    cmake -S "${expat_source}" -B "${build_root}/expat" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/System \
        -DCMAKE_INSTALL_LIBDIR=Libraries/Graphics \
        -DCMAKE_INSTALL_INCLUDEDIR=Development/Headers \
        -DCMAKE_INSTALL_RPATH="${library_prefix}:/System/Libraries" \
        -DEXPAT_BUILD_DOCS=OFF \
        -DEXPAT_BUILD_EXAMPLES=OFF \
        -DEXPAT_BUILD_FUZZERS=OFF \
        -DEXPAT_BUILD_TESTS=OFF \
        -DEXPAT_BUILD_TOOLS=OFF \
        -DEXPAT_SHARED_LIBS=ON \
        -DEXPAT_WARNINGS_AS_ERRORS=OFF \
        -DEXPAT_WITH_LIBBSD=OFF
    cmake --build "${build_root}/expat" --parallel "${MIXTAR_JOBS}"
    DESTDIR="${sysroot}" cmake --install "${build_root}/expat" --strip

    export PKG_CONFIG_SYSROOT_DIR="${sysroot}"
    export PKG_CONFIG_LIBDIR="${sysroot}/System/Libraries/Graphics/pkgconfig:${sysroot}/System/Share/pkgconfig"
    export PATH="${sysroot}/System/Commands:${PATH}"
    export LD_LIBRARY_PATH="${sysroot}/System/Libraries/Graphics"
    export CFLAGS="-O2 -pipe -fno-plt -ffunction-sections -fdata-sections"
    export CXXFLAGS="${CFLAGS}"
    export LDFLAGS="-Wl,-O1,--as-needed,--gc-sections -Wl,-rpath,${library_prefix}:/System/Libraries"
    export SOURCE_DATE_EPOCH="${MIXTAR_SOURCE_DATE_EPOCH}"
    export ZERO_AR_DATE=1

    libffi_source="$(prepare_source libffi)"
    mkdir -p "${build_root}/libffi"
    (
        cd "${build_root}/libffi"
        "${libffi_source}/configure" \
            --prefix=/System \
            --libdir="${library_prefix}" \
            --includedir=/System/Development/Headers \
            --disable-docs \
            --disable-multi-os-directory \
            --disable-static \
            --enable-shared
        make -s -j"${MIXTAR_JOBS}"
        make -s DESTDIR="${sysroot}" install
    )

    wayland_source="$(prepare_source wayland)"
    meson_install wayland "${wayland_source}" \
        --bindir=Commands \
        -Ddocumentation=false \
        -Ddtd_validation=false \
        -Dlibraries=true \
        -Dscanner=true \
        -Dtests=false

    protocols_source="$(prepare_source wayland-protocols)"
    meson_install wayland-protocols "${protocols_source}" -Dtests=false

    freetype_source="$(prepare_source freetype)"
    meson_install freetype "${freetype_source}" \
        -Dbrotli=disabled \
        -Dbzip2=disabled \
        -Dharfbuzz=disabled \
        -Dmmap=enabled \
        -Dpng=disabled \
        -Dtests=disabled \
        -Dzlib=disabled

    harfbuzz_source="$(prepare_source harfbuzz)"
    meson_install harfbuzz "${harfbuzz_source}" \
        -Dbenchmark=disabled \
        -Dcairo=disabled \
        -Dchafa=disabled \
        -Ddocs=disabled \
        -Dfreetype=enabled \
        -Dglib=disabled \
        -Dgobject=disabled \
        -Dgraphite2=disabled \
        -Dicu=disabled \
        -Dintrospection=disabled \
        -Dtests=disabled \
        -Dutilities=disabled

    fontconfig_source="$(prepare_source fontconfig)"
    meson_install fontconfig "${fontconfig_source}" \
        --sysconfdir=/System/Configuration \
        --localstatedir=/System/State \
        -Dadditional-fonts-dirs= \
        -Dbaseconfig-dir=/System/Configuration/Fonts \
        -Dcache-build=disabled \
        -Dcache-dir=/System/State/FontCache \
        -Dconfig-dir=/System/Configuration/Fonts/conf.d \
        -Ddefault-fonts-dirs=/System/Fonts \
        -Ddoc=disabled \
        -Ddoc-html=disabled \
        -Ddoc-man=disabled \
        -Ddoc-pdf=disabled \
        -Ddoc-txt=disabled \
        -Dnls=disabled \
        -Dtests=disabled \
        -Dtools=disabled

    libdrm_source="$(prepare_source libdrm)"
    meson_install libdrm "${libdrm_source}" \
        -Damdgpu=disabled \
        -Dcairo-tests=disabled \
        -Detnaviv=disabled \
        -Dexynos=disabled \
        -Dfreedreno=disabled \
        -Dintel=disabled \
        -Dman-pages=disabled \
        -Dnouveau=disabled \
        -Domap=disabled \
        -Dradeon=disabled \
        -Dtegra=disabled \
        -Dtests=false \
        -Dvalgrind=disabled \
        -Dvc4=disabled \
        -Dvmwgfx=disabled

    mesa_source="$(prepare_source mesa)"
    meson_install mesa "${mesa_source}" \
        -Dbuild-tests=false \
        -Degl=enabled \
        -Degl-native-platform=wayland \
        -Dgallium-drivers=softpipe,virgl \
        -Dgallium-va=disabled \
        -Dgallium-vdpau=disabled \
        -Dgallium-xa=disabled \
        -Dgbm=enabled \
        -Dgles1=disabled \
        -Dgles2=enabled \
        -Dglvnd=disabled \
        -Dglx=disabled \
        -Dlibunwind=disabled \
        -Dllvm=disabled \
        -Dlmsensors=disabled \
        -Dopengl=false \
        -Dplatforms=wayland \
        -Dshader-cache=disabled \
        -Dshared-glapi=enabled \
        -Dshared-llvm=disabled \
        -Dvalgrind=disabled \
        -Dvideo-codecs=[] \
        -Dvulkan-drivers=[] \
        -Dxmlconfig=disabled

    copy_runtime_library cc libpthread.so.0
    copy_runtime_library cc libdl.so.2
    copy_runtime_library cc librt.so.1
    copy_runtime_library cc libgcc_s.so.1
    copy_runtime_library cc libatomic.so.1
    copy_runtime_library c++ libstdc++.so.6

    mkdir -p "${sysroot}/System/Fonts" "${sysroot}/System/Licenses/Fonts"
    unzip -p "${archive_root}/$(component_value noto-sans archive)" \
        NotoSans/hinted/ttf/NotoSans-Regular.ttf > "${sysroot}/System/Fonts/NotoSans-Regular.ttf"
    unzip -p "${archive_root}/$(component_value noto-sans archive)" \
        NotoSans/hinted/ttf/NotoSans-Bold.ttf > "${sysroot}/System/Fonts/NotoSans-Bold.ttf"
    unzip -p "${archive_root}/$(component_value noto-sans archive)" OFL.txt \
        > "${sysroot}/System/Licenses/Fonts/NotoSans.OFL.txt"
    unzip -p "${archive_root}/$(component_value noto-sans-mono archive)" \
        NotoSansMono/hinted/ttf/NotoSansMono-Regular.ttf > "${sysroot}/System/Fonts/NotoSansMono-Regular.ttf"
    unzip -p "${archive_root}/$(component_value noto-sans-mono archive)" \
        NotoSansMono/hinted/ttf/NotoSansMono-Bold.ttf > "${sysroot}/System/Fonts/NotoSansMono-Bold.ttf"
    unzip -p "${archive_root}/$(component_value noto-sans-mono archive)" OFL.txt \
        > "${sysroot}/System/Licenses/Fonts/NotoSansMono.OFL.txt"

    copy_license "${expat_source}" Expat.txt COPYING
    copy_license "${libffi_source}" Libffi.txt LICENSE
    copy_license "${wayland_source}" Wayland.txt COPYING
    copy_license "${protocols_source}" WaylandProtocols.txt COPYING
    copy_license "${freetype_source}" FreeType.txt LICENSE.TXT
    copy_license "${harfbuzz_source}" HarfBuzz.txt COPYING
    copy_license "${fontconfig_source}" Fontconfig.txt COPYING
    collect_libdrm_licenses "${libdrm_source}"
    copy_license "${mesa_source}" Mesa.txt docs/license.rst COPYING

    rm -rf -- \
        "${sysroot}/System/Commands" \
        "${sysroot}/System/Configuration" \
        "${sysroot}/System/Development" \
        "${sysroot}/System/Share" \
        "${sysroot}/System/State"

    if [[ -d "${sysroot}/System/Libraries/Graphics/dri" ]]; then
        find "${sysroot}/System/Libraries/Graphics/dri" -maxdepth 1 \
            \( -type f -o -type l \) \
            ! -name 'swrast_dri.so' \
            ! -name 'kms_swrast_dri.so' \
            ! -name 'virtio_gpu_dri.so' \
            -delete
    fi

    touch -d "@${MIXTAR_SOURCE_DATE_EPOCH}" "${complete_marker}"
    build_seconds=$(( $(date +%s) - build_started ))
else
    build_seconds=0
fi

rm -rf -- "${output}"
mkdir -p "${output}/Root/System"
cp -aL "${sysroot}/System/." "${output}/Root/System/"

if find "${output}/Root" -type l -print -quit | grep -q .; then
    printf 'Graphics stack output contains a symbolic link.\n' >&2
    exit 4
fi

cat > "${output}/Build.json" <<EOF
{
  "schema": "mixtar.graphics-build.v1",
  "stack_key": "${MIXTAR_STACK_KEY}",
  "source_date_epoch": ${MIXTAR_SOURCE_DATE_EPOCH},
  "jobs": ${MIXTAR_JOBS},
  "build_seconds": ${build_seconds},
  "prefix": "/System"
}
EOF

printf '%s\n' "${output}/Build.json"
