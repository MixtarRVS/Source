#!/bin/sh
set -u

VERSION=0.4
KERNEL_LAYOUT_VERSION=7.1.2
RT_VERSION=7.1.2-mixtar-rt
ROOT=${2:-/}
ESP=${3:-/boot/efi}

root_path() {
	case "$ROOT" in
		/) printf '%s\n' "$1" ;;
		*) printf '%s\n' "$ROOT$1" ;;
	esac
}

PROFILE_DIR=$(root_path "/System/Kernel/Linux/RT/$KERNEL_LAYOUT_VERSION")
PROFILE_JSON=$PROFILE_DIR/kernel-profile.json
ROOT_EFI=$(root_path "/System/EFI/MixtarRVS/$VERSION.efi")
ESP_EFI=$ESP/EFI/MixtarRVS/$VERSION.efi

trim_root() {
	root_path "$1"
}

exists() {
	test -e "$1" -o -L "$1"
}

contains() {
	file=$1
	text=$2
	test -f "$file" && grep -F "$text" "$file" >/dev/null 2>&1
}

fail() {
	printf 'fail: %s\n' "$1"
	FAILED=1
}

pass() {
	printf 'ok: %s\n' "$1"
}

audit() {
	printf 'corev04.version=%s\n' "$VERSION"
	printf 'corev04.kernel_layout_version=%s\n' "$KERNEL_LAYOUT_VERSION"
	printf 'corev04.required_kernel_profile=rt\n'
	printf 'corev04.required_kernel_version=%s\n' "$RT_VERSION"
	printf 'corev04.required_boot_mode=single-uki\n'
	printf 'root=%s\n' "$ROOT"
	printf 'esp=%s\n' "$ESP"
	printf 'profile_dir=%s\n' "$PROFILE_DIR"
	printf 'profile_json=%s\n' "$PROFILE_JSON"
	printf 'root_efi=%s\n' "$ROOT_EFI"
	printf 'esp_efi=%s\n' "$ESP_EFI"
	printf 'runtime_uname='
	uname -r 2>/dev/null || true
	printf 'runtime_cmdline='
	cat /proc/cmdline 2>/dev/null || true
}

verify() {
	FAILED=0

	exists "$PROFILE_DIR" && pass "rt profile directory exists" || fail "missing $PROFILE_DIR"
	exists "$PROFILE_JSON" && pass "kernel profile manifest exists" || fail "missing $PROFILE_JSON"
	exists "$ROOT_EFI" && pass "root UKI exists" || fail "missing $ROOT_EFI"
	exists "$ESP_EFI" && pass "ESP UKI exists" || fail "missing $ESP_EFI"

	contains "$PROFILE_JSON" '"profile": "rt"' && pass "manifest profile is rt" || fail "manifest does not declare profile rt"
	contains "$PROFILE_JSON" '"version": "7.1.2-mixtar-rt"' && pass "manifest kernel version matches" || fail "manifest kernel version mismatch"
	contains "$PROFILE_JSON" '"mode": "single-uki"' && pass "manifest boot mode is single-uki" || fail "manifest boot mode is not single-uki"
	contains "$PROFILE_JSON" '"debian": "build-host-only"' && pass "manifest keeps Debian as build host only" || fail "manifest does not mark Debian build-host-only"

	for p in \
		"$PROFILE_DIR/modules/$RT_VERSION" \
		"$PROFILE_DIR/config-$RT_VERSION" \
		"$PROFILE_DIR/System.map-$RT_VERSION"
	do
		if exists "$p"; then
			pass "official RT layout member exists: $p"
		else
			fail "missing official RT layout member: $p"
		fi
	done

	for p in \
		"$(root_path "/System/Kernel/Current")" \
		"$(root_path "/System/EFI/MixtarRVS/Current.efi")" \
		"$(root_path "/System/EFI/MixtarRVS/Previous.efi")" \
		"$ESP/EFI/MixtarRVS/Current.efi" \
		"$ESP/EFI/MixtarRVS/Previous.efi" \
		"$ESP/EFI/MixtarRVS/MixtarRVS.efi" \
		"$ESP/EFI/MixtarRVS/MixtarRVS-CoreV01.efi" \
		"$ESP/EFI/mixtarrvs-rt/vmlinuz.efi"
	do
		if exists "$p"; then
			fail "forbidden legacy boot artifact exists: $p"
		else
			pass "forbidden legacy boot artifact absent: $p"
		fi
	done

	for p in \
		"$(root_path "/boot/vmlinuz-$RT_VERSION")" \
		"$(root_path "/boot/initrd.img-$RT_VERSION")"
	do
		if exists "$p"; then
			fail "RT kernel is still exposed to rescue GRUB: $p"
		else
			pass "RT kernel not exposed to rescue GRUB: $p"
		fi
	done

	for p in \
		"$PROFILE_DIR/vmlinuz-$RT_VERSION" \
		"$PROFILE_DIR/initrd.img-$RT_VERSION" \
		"$PROFILE_DIR/vmlinuz" \
		"$PROFILE_DIR/initramfs.img"
	do
		if exists "$p"; then
			fail "split kernel/initramfs artifact is inside official RT profile: $p"
		else
			pass "official RT profile has no split boot artifact: $p"
		fi
	done

	GRUB_CFG=$(root_path "/boot/grub/grub.cfg")
	if test -f "$GRUB_CFG"; then
		if grep -F "$RT_VERSION" "$GRUB_CFG" >/dev/null 2>&1; then
			fail "rescue GRUB still references RT kernel"
		else
			pass "rescue GRUB has no RT kernel references"
		fi
	fi

	return "$FAILED"
}

stage() {
	target=$(trim_root "/System/Kernel/Linux/RT/$KERNEL_LAYOUT_VERSION/corev04-verify-latest.txt")
	dir=$(dirname "$target")
	install -d -m 0755 "$dir"
	{
		audit
		verify
	} > "$target"
}

case "${1:-audit}" in
	audit)
		audit
		;;
	verify)
		verify
		;;
	stage)
		stage
		;;
	*)
		printf 'usage: %s [audit|verify|stage] [root] [esp]\n' "$0" >&2
		exit 2
		;;
esac
