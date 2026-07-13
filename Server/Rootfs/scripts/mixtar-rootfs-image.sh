#!/System/Tools/Current/bin/sh
set -u

PROFILE=${MIXTAR_ROOTFS_IMAGE_PROFILE:-/System/Config/ImageBuilder/rootfs-image.requirements}

usage() {
	cat >&2 <<EOF
usage: mixtar-rootfs-image <command>

commands:
  contract
  check
  requirements
  inputs
  exclusions
  plan
  backend
  readiness
  inspect
  contents-check
  mount-plan
  mount-inspect --once
  file-manifest
  current-manifest
  diff-current
  hash-sample
  switch-readiness
  switch-plan
  initramfs-handoff-plan
  build --dry-run
  build --first-file
EOF
}

field() {
	key=$1
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PROFILE"
}

fields() {
	key=$1
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print }' "$PROFILE"
}

tool_state() {
	name=$1
	path=$(command -v "$name" 2>/dev/null || true)
	if [ -n "$path" ]; then
		echo "$name=$path"
	else
		echo "$name=missing"
	fi
}

default_image() {
	echo "/System/Generations/0015-rootfs-image-first-file/rootfs.squashfs"
}

inspect_image() {
	image=$(default_image)
	echo "image=$image"
	if [ ! -s "$image" ]; then
		echo "image_status=missing-or-empty"
		return 1
	fi
	echo "image_status=present"
	wc -c "$image" | awk '{ print "size_bytes=" $1 }'
	sha256sum "$image" | awk '{ print "sha256=" $1 }'
	unsquashfs -s "$image"
}

check_list_path() {
	list_file=$1
	label=$2
	path=$3
	if grep -F "squashfs-root/$path" "$list_file" >/dev/null 2>&1; then
		echo "$label=present"
		return 0
	fi
	echo "$label=missing"
	return 1
}

contents_check() {
	image=$(default_image)
	list_file=/tmp/mixtar-rootfs-image-contents.$$
	rc=0
	if [ ! -s "$image" ]; then
		echo "image_status=missing-or-empty"
		return 1
	fi
	if ! unsquashfs -ll "$image" > "$list_file" 2>/dev/null; then
		echo "list_status=failed"
		rm -f "$list_file"
		return 1
	fi
	echo "list_status=ok"
	check_list_path "$list_file" "path_System" "System" || rc=1
	check_list_path "$list_file" "path_System_Tools_alias" "System/Tools" || rc=1
	check_list_path "$list_file" "path_bin_Current" "bin/Current" || rc=1
	check_list_path "$list_file" "path_bin_MixtarRVS_bin" "bin/MixtarRVS/bin" || rc=1
	check_list_path "$list_file" "path_System_SystemTools_alias" "System/SystemTools" || rc=1
	check_list_path "$list_file" "path_sbin_mixtar_rootfs_image" "sbin/mixtar-rootfs-image" || rc=1
	check_list_path "$list_file" "path_System_Kernel_Current" "System/Kernel/Current" || rc=1
	check_list_path "$list_file" "path_System_Config_alias" "System/Config" || rc=1
	check_list_path "$list_file" "path_etc_Services" "etc/Services" || rc=1
	check_list_path "$list_file" "path_etc_Network" "etc/Network/current.network" || rc=1
	check_list_path "$list_file" "path_etc_RemoteAccess" "etc/RemoteAccess/current.remote" || rc=1
	check_list_path "$list_file" "path_etc_ImageBuilder" "etc/ImageBuilder/rootfs-image.requirements" || rc=1
	check_list_path "$list_file" "path_System_Libraries_alias" "System/Libraries" || rc=1
	check_list_path "$list_file" "path_lib_MixtarRVS_Runtime" "lib/MixtarRVS/Runtime/0003/lib" || rc=1
	check_list_path "$list_file" "path_bin" "bin" || rc=1
	check_list_path "$list_file" "path_sbin" "sbin" || rc=1
	check_list_path "$list_file" "path_lib" "lib" || rc=1
	check_list_path "$list_file" "path_usr" "usr" || rc=1
	check_list_path "$list_file" "path_etc" "etc" || rc=1
	if grep -F "squashfs-root/System/Generations/0015-rootfs-image-first-file" "$list_file" >/dev/null 2>&1; then
		echo "self_include=present"
		rc=1
	else
		echo "self_include=absent"
	fi
	rm -f "$list_file"
	if [ "$rc" -eq 0 ]; then
		echo "contents_check=ok"
	fi
	return "$rc"
}

mount_plan() {
	image=$(default_image)
	mount_point=/System/Runtime/Inspect/rootfs-0015
	echo "mount_plan=inspect-only"
	echo "would_mount=false"
	echo "requires_root=true"
	echo "image=$image"
	echo "mount_point=$mount_point"
	echo "mount_command=mount -t squashfs -o loop,ro $image $mount_point"
	echo "umount_command=umount $mount_point"
	echo "safety=do-not-use-as-rootfs"
	echo "activation=none"
}

is_mounted() {
	mount_point=$1
	awk -v mount_point="$mount_point" '$2 == mount_point { found = 1 } END { exit found ? 0 : 1 }' /proc/mounts 2>/dev/null
}

check_mounted_path() {
	label=$1
	path=$2
	if [ -e "$path" ]; then
		echo "$label=present"
		return 0
	fi
	echo "$label=missing"
	return 1
}

mount_inspect_once() {
	image=$(default_image)
	mount_point=/System/Runtime/Inspect/rootfs-0015
	rc=0
	if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
		echo "mount-inspect --once requires root" >&2
		return 1
	fi
	if [ ! -s "$image" ]; then
		echo "image_status=missing-or-empty"
		return 1
	fi
	if is_mounted "$mount_point"; then
		echo "mount_status=already-mounted"
		return 1
	fi
	install -d -m 0755 "$mount_point"
	echo "mount_plan=inspect-only"
	echo "image=$image"
	echo "mount_point=$mount_point"
	echo "would_use_as_rootfs=false"
	if mount -t squashfs -o loop,ro "$image" "$mount_point"; then
		echo "mount_status=mounted"
	else
		echo "mount_status=failed"
		return 1
	fi
	awk -v mount_point="$mount_point" '$2 == mount_point { print "mount_line=" $0 }' /proc/mounts 2>/dev/null
	check_mounted_path mounted_path_System "$mount_point/System" || rc=1
	check_mounted_path mounted_path_System_Tools_Current "$mount_point/System/Tools/Current" || rc=1
	check_mounted_path mounted_path_System_SystemTools "$mount_point/System/SystemTools" || rc=1
	check_mounted_path mounted_path_System_Kernel_Current "$mount_point/System/Kernel/Current" || rc=1
	check_mounted_path mounted_path_etc_Network "$mount_point/etc/Network/current.network" || rc=1
	check_mounted_path mounted_path_etc_RemoteAccess "$mount_point/etc/RemoteAccess/current.remote" || rc=1
	check_mounted_path mounted_path_etc_ImageBuilder "$mount_point/etc/ImageBuilder/rootfs-image.requirements" || rc=1
	check_mounted_path mounted_path_lib_Runtime "$mount_point/lib/MixtarRVS/Runtime/0003/lib" || rc=1
	check_mounted_path mounted_path_bin "$mount_point/bin" || rc=1
	check_mounted_path mounted_path_sbin "$mount_point/sbin" || rc=1
	if [ -e "$mount_point/System/Generations/0015-rootfs-image-first-file" ]; then
		echo "mounted_self_include=present"
		rc=1
	else
		echo "mounted_self_include=absent"
	fi
	if umount "$mount_point"; then
		echo "unmount_status=unmounted"
	else
		echo "unmount_status=failed"
		rc=1
	fi
	if is_mounted "$mount_point"; then
		echo "mount_after=present"
		rc=1
	else
		echo "mount_after=absent"
	fi
	if [ "$rc" -eq 0 ]; then
		echo "mount_inspect_result=ok"
	fi
	return "$rc"
}

image_manifest_paths() {
	image=$(default_image)
	unsquashfs -ll "$image" 2>/dev/null | awk '
		/squashfs-root/ {
			line = $0
			sub(/^.*squashfs-root\/?/, "", line)
			sub(/ -> .*/, "", line)
			if (line == "") {
				line = "."
			}
			print line
		}
	' | sort -u
}

current_manifest_paths() {
	find / -xdev \
		\( \
			-path /dev -o \
			-path /proc -o \
			-path /sys -o \
			-path /run -o \
			-path /tmp -o \
			-path /Temporary -o \
			-path /Users -o \
			-path /Volumes -o \
			-path /System/Runtime/run -o \
			-path /System/Logs -o \
			-path /var/cache/apk -o \
			-path /mnt -o \
			-path /media -o \
			-path /lost+found \
		\) -prune -o -print 2>/dev/null | awk '
		{
			sub("^/", "", $0)
			if ($0 == "") {
				print "."
			} else {
				print $0
			}
		}
	' | sort -u
}

file_manifest() {
	image=$(default_image)
	if [ ! -s "$image" ]; then
		echo "missing image: $image" >&2
		return 1
	fi
	image_manifest_paths
}

current_manifest() {
	current_manifest_paths
}

diff_current() {
	image_tmp=/tmp/mixtar-image-manifest.$$
	current_tmp=/tmp/mixtar-current-manifest.$$
	image_only=/tmp/mixtar-image-only.$$
	current_only=/tmp/mixtar-current-only.$$
	image_manifest_paths > "$image_tmp"
	current_manifest_paths > "$current_tmp"
	comm -23 "$image_tmp" "$current_tmp" > "$image_only"
	comm -13 "$image_tmp" "$current_tmp" > "$current_only"
	echo "diff_status=generated"
	echo "image_path_count=$(wc -l < "$image_tmp" | awk '{ print $1 }')"
	echo "current_path_count=$(wc -l < "$current_tmp" | awk '{ print $1 }')"
	echo "image_only_count=$(wc -l < "$image_only" | awk '{ print $1 }')"
	echo "current_only_count=$(wc -l < "$current_only" | awk '{ print $1 }')"
	echo "image_only_sample_begin"
	sed -n '1,40p' "$image_only"
	echo "image_only_sample_end"
	echo "current_only_sample_begin"
	sed -n '1,40p' "$current_only"
	echo "current_only_sample_end"
	rm -f "$image_tmp" "$current_tmp" "$image_only" "$current_only"
}

hash_one_path() {
	image=$1
	path=$2
	current="/$path"
	image_hash=$(unsquashfs -cat "$image" "$path" 2>/dev/null | sha256sum | awk '{ print $1 }')
	if [ -f "$current" ]; then
		current_hash=$(sha256sum "$current" 2>/dev/null | awk '{ print $1 }')
		current_state=present
	else
		current_hash=missing
		current_state=missing
	fi
	if [ "$image_hash" = "$current_hash" ]; then
		match=true
	else
		match=false
	fi
	echo "sample=$path image_sha256=$image_hash current_sha256=$current_hash current_state=$current_state match=$match"
}

hash_sample() {
	image=$(default_image)
	if [ ! -s "$image" ]; then
		echo "missing image: $image" >&2
		return 1
	fi
	echo "hash_sample=image-vs-current"
	echo "image=$image"
	for path in \
		etc/os-release \
		etc/alpine-release \
		etc/mixtar-release \
		etc/Services/network.service \
		etc/Network/current.network \
		etc/RemoteAccess/current.remote \
		etc/ImageBuilder/rootfs-image.requirements \
		System/Kernel/Profiles/rt-7.1.2-mixtar-rt/profile.json \
		lib/MixtarRVS/Runtime/0003/lib/ld-musl-x86_64.so.1 \
		bin/MixtarRVS/bin/ls \
		bin/MixtarRVS/bin/sh \
		sbin/mixtar-rootfs-image
	do
		hash_one_path "$image" "$path"
	done
}

switch_readiness() {
	image=$(default_image)
	rc=0
	echo "switch_readiness=non-activating"
	echo "image=$image"
	if [ -s "$image" ]; then
		echo "rootfs_image_ready=true"
	else
		echo "rootfs_image_ready=false"
		rc=1
	fi
	if [ -f /System/Generations/0015-rootfs-image-first-file/manifest.json ]; then
		echo "generation_manifest_ready=true"
	else
		echo "generation_manifest_ready=false"
		rc=1
	fi
	if [ -f /System/Generations/0015-rootfs-image-first-file/activation.plan ]; then
		echo "activation_plan_present=true"
	else
		echo "activation_plan_present=false"
		rc=1
	fi
	if grep -F 'activation=none' /System/Generations/0015-rootfs-image-first-file/activation.plan >/dev/null 2>&1; then
		echo "activation_plan_is_non_activating=true"
	else
		echo "activation_plan_is_non_activating=false"
		rc=1
	fi
	if [ -f /System/Base/Closure/0018-rootfs-image-file-manifest-and-diff/manifest-diff-summary.txt ]; then
		echo "path_diff_ready=true"
		grep -F 'image_only_count=' /System/Base/Closure/0018-rootfs-image-file-manifest-and-diff/manifest-diff-summary.txt
		grep -F 'current_only_count=' /System/Base/Closure/0018-rootfs-image-file-manifest-and-diff/manifest-diff-summary.txt
	else
		echo "path_diff_ready=false"
		rc=1
	fi
	if contents_check >/dev/null 2>&1; then
		echo "contents_check_ready=true"
	else
		echo "contents_check_ready=false"
		rc=1
	fi
	echo "current_target=$(readlink /System/Current 2>/dev/null || true)"
	echo "future_switch_ready=false"
	echo "switch_blocker=initramfs image-root handoff, bootloader entry, rollback policy, and garbage collection not implemented"
	echo "would_switch_current=false"
	echo "would_change_bootloader=false"
	echo "would_rebuild_initramfs=false"
	return "$rc"
}

switch_plan() {
	image=$(default_image)
	generation_id=0015-rootfs-image-first-file
	generation_dir=/System/Generations/$generation_id
	current_target=$(readlink /System/Current 2>/dev/null || true)
	rc=0
	echo "switch_plan=non-activating"
	echo "plan_stage=0020-switch-plan-no-activation"
	echo "source_generation=$generation_id"
	echo "source_generation_dir=$generation_dir"
	echo "rootfs_image=$image"
	if [ -s "$image" ]; then
		echo "rootfs_image_ready=true"
		wc -c "$image" | awk '{ print "rootfs_size_bytes=" $1 }'
		sha256sum "$image" | awk '{ print "rootfs_sha256=" $1 }'
	else
		echo "rootfs_image_ready=false"
		rc=1
	fi
	if [ -f "$generation_dir/manifest.json" ]; then
		echo "generation_manifest_ready=true"
	else
		echo "generation_manifest_ready=false"
		rc=1
	fi
	if [ -f "$generation_dir/activation.plan" ]; then
		echo "activation_plan_present=true"
	else
		echo "activation_plan_present=false"
		rc=1
	fi
	if grep -F 'activation=none' "$generation_dir/activation.plan" >/dev/null 2>&1; then
		echo "activation_plan_is_non_activating=true"
	else
		echo "activation_plan_is_non_activating=false"
		rc=1
	fi
	if contents_check >/dev/null 2>&1; then
		echo "contents_check_ready=true"
	else
		echo "contents_check_ready=false"
		rc=1
	fi
	if [ -f /System/Base/Closure/0019-rootfs-image-content-hash-sample-and-switch-readiness/rootfs-image-content-hash-sample-and-switch-readiness-status.txt ]; then
		stage_0019_status=$(cat /System/Base/Closure/0019-rootfs-image-content-hash-sample-and-switch-readiness/rootfs-image-content-hash-sample-and-switch-readiness-status.txt)
		echo "stage_0019_status=$stage_0019_status"
		if [ "$stage_0019_status" != "verified" ]; then
			rc=1
		fi
	else
		echo "stage_0019_status=missing"
		rc=1
	fi
	echo "current_target=$current_target"
	echo "fallback_generation=$current_target"
	echo "target_current=Generations/$generation_id"
	echo "previous_generation_preserved=true"
	echo "activation_allowed=false"
	echo "future_switch_ready=false"
	echo "would_switch_current=false"
	echo "would_write_current_link=false"
	echo "would_change_bootloader=false"
	echo "would_write_boot_entry=false"
	echo "would_rebuild_initramfs=false"
	echo "would_mount_rootfs=false"
	echo "would_delete_previous=false"
	echo "required_before_activation=initramfs-image-root-handoff"
	echo "required_before_activation=bootloader-fallback-entry"
	echo "required_before_activation=rollback-policy"
	echo "required_before_activation=garbage-collection-policy"
	echo "next_required_stage=0021-initramfs-image-root-handoff-plan"
	echo "planned_activation_sequence_begin"
	echo "step01=build boot-capable generation from rootfs image"
	echo "step02=teach initramfs to mount /System/Current/rootfs.squashfs as read-only image root"
	echo "step03=add writable tmpfs or persistent overlay policy"
	echo "step04=preserve current fallback generation and boot entry"
	echo "step05=switch /System/Current only after boot contract and rollback are verified"
	echo "planned_activation_sequence_end"
	return "$rc"
}

report_file_status() {
	label=$1
	path=$2
	if [ -f "$path" ]; then
		echo "$label=true"
		wc -c "$path" 2>/dev/null | awk -v label="$label" '{ print label "_size_bytes=" $1 }'
		sha256sum "$path" 2>/dev/null | awk -v label="$label" '{ print label "_sha256=" $1 }'
		return 0
	fi
	echo "$label=false"
	return 1
}

initramfs_handoff_plan() {
	image=$(default_image)
	generation_id=0015-rootfs-image-first-file
	generation_dir=/System/Generations/$generation_id
	current_target=$(readlink /System/Current 2>/dev/null || true)
	kernel_profile_target=$(readlink /System/Kernel/Current 2>/dev/null || true)
	kernel_current=/System/Kernel/Current
	vmlinuz=$kernel_current/vmlinuz
	initramfs=$kernel_current/initramfs.img
	modules_dir=$kernel_current/modules
	rc=0
	echo "initramfs_handoff_plan=non-activating"
	echo "plan_stage=0021-initramfs-image-root-handoff-plan"
	echo "current_target=$current_target"
	echo "source_generation=$generation_id"
	echo "source_generation_dir=$generation_dir"
	echo "rootfs_image=$image"
	if [ -s "$image" ]; then
		echo "rootfs_image_ready=true"
		wc -c "$image" | awk '{ print "rootfs_size_bytes=" $1 }'
		sha256sum "$image" | awk '{ print "rootfs_sha256=" $1 }'
	else
		echo "rootfs_image_ready=false"
		rc=1
	fi
	echo "kernel_profile_current=$kernel_profile_target"
	report_file_status kernel_vmlinuz_ready "$vmlinuz" || rc=1
	report_file_status kernel_initramfs_ready "$initramfs" || rc=1
	if [ -d "$modules_dir" ]; then
		echo "kernel_modules_ready=true"
	else
		echo "kernel_modules_ready=false"
		rc=1
	fi
	if grep -w squashfs /proc/filesystems >/dev/null 2>&1; then
		echo "kernel_squashfs_ready=true"
	else
		echo "kernel_squashfs_ready=false"
		rc=1
	fi
	if grep -w overlay /proc/filesystems >/dev/null 2>&1; then
		echo "kernel_overlay_ready=true"
	else
		echo "kernel_overlay_ready=false"
	fi
	if command -v switch_root >/dev/null 2>&1; then
		echo "switch_root_tool_ready=true"
	else
		echo "switch_root_tool_ready=false"
	fi
	echo "current_cmdline=$(cat /proc/cmdline 2>/dev/null || true)"
	echo "current_boot_root_mode=block-root-ext4"
	echo "planned_boot_root_mode=image-root-squashfs-readonly-plus-overlay"
	echo "planned_base_mount=/MixtarBase"
	echo "planned_image_mount=/MixtarImage"
	echo "planned_overlay_upper=/MixtarOverlay/upper"
	echo "planned_overlay_work=/MixtarOverlay/work"
	echo "planned_new_root=/MixtarRoot"
	echo "planned_rootfs_path=/System/Current/rootfs.squashfs"
	echo "planned_init_primary=/System/SystemTools/init"
	echo "planned_init_fallback=/sbin/init"
	echo "planned_kernel_args=mixtar.rootfs=/System/Current/rootfs.squashfs mixtar.overlay=tmpfs mixtar.fallback=previous"
	echo "required_initramfs_feature=mount-devtmpfs"
	echo "required_initramfs_feature=mount-procfs"
	echo "required_initramfs_feature=mount-sysfs"
	echo "required_initramfs_feature=mount-base-root-readonly"
	echo "required_initramfs_feature=resolve-system-current"
	echo "required_initramfs_feature=mount-squashfs-image"
	echo "required_initramfs_feature=create-tmpfs-overlay"
	echo "required_initramfs_feature=validate-target-init"
	echo "required_initramfs_feature=switch-root"
	echo "required_initramfs_feature=fallback-to-block-root"
	echo "would_rebuild_initramfs=false"
	echo "would_write_initramfs=false"
	echo "would_change_bootloader=false"
	echo "would_switch_current=false"
	echo "activation_allowed=false"
	echo "future_handoff_ready=false"
	echo "handoff_blocker=initramfs implementation not built or installed"
	echo "next_required_stage=0022-initramfs-handoff-prototype-no-install"
	return "$rc"
}

contract() {
	cat <<EOF
MixtarRVS rootfs image builder requirements contract:
  profile: $PROFILE
  format: squashfs
  required builder: mksquashfs
  current status: requirements only

Implemented:
  check
  requirements
  inputs
  exclusions
  plan
  backend
  readiness
  inspect
  contents-check
  mount-plan
  mount-inspect --once
  file-manifest
  current-manifest
  diff-current
  hash-sample
  switch-readiness
  switch-plan
  initramfs-handoff-plan
  build --dry-run
  build --first-file

Not implemented yet:
  initramfs rebuild
  activation/switch
  rollback
  garbage collection
EOF
}

requirements() {
	cat "$PROFILE"
}

inputs() {
	echo "source_root=$(field source_root)"
	echo "generation_root=$(field generation_root)"
	echo "kernel_profile=$(field kernel_profile)"
	echo "kernel_vmlinuz=$(field kernel_profile)/vmlinuz"
	echo "kernel_initramfs=$(field kernel_profile)/initramfs.img"
	echo "toolkit_root=$(field toolkit_root)"
	echo "runtime_libraries=$(field runtime_libraries)"
	echo "generation_profile=$(field generation_profile)"
	echo "service_profile=$(field service_profile)"
	echo "network_profile=$(field network_profile)"
	echo "remote_profile=$(field remote_profile)"
}

exclusions() {
	fields exclude | awk '{ print "exclude=" $0 }'
}

plan() {
	echo "plan=rootfs-image-build-requirements"
	echo "mode=requirements-only"
	echo "would_create_rootfs_image=false"
	echo "would_create_generation=false"
	echo "would_mount_filesystems=false"
	echo "would_run_mksquashfs=false"
	echo "would_rebuild_initramfs=false"
	echo "would_switch_current=false"
	echo "format=$(field format)"
	echo "required_builder=$(field required_builder)"
	echo "future_output=$(field future_output)"
	echo "future_manifest=$(field future_manifest)"
	echo "future_activation=$(field future_activation)"
	echo "activation_policy=$(field activation_policy)"
	echo "rollback_policy=$(field rollback_policy)"
	inputs
	exclusions
}

backend() {
	echo "format=$(field format)"
	echo "required_builder=$(field required_builder)"
	echo "builder_package=$(field builder_package)"
	tool_state mksquashfs
	tool_state unsquashfs
	tool_state tar
	tool_state gzip
	tool_state xz
	tool_state zstd
	tool_state sha256sum
	tool_state find
	tool_state sort
	tool_state du
}

input_size_report() {
	for path in /System /bin /sbin /lib /usr /etc; do
		if [ -e "$path" ]; then
			du -sk "$path" 2>/dev/null | awk -v path="$path" '{ print "input_size_kib=" path ":" $1 }'
		else
			echo "input_size_kib=$path:missing"
		fi
	done
}

mksquashfs_exclusions() {
	fields exclude | awk '
		{
			path = $0
			sub("^/", "", path)
			if (path != "") {
				printf " %s", path
			}
		}
		END { printf "\n" }
	'
}

build_dry_run() {
	generation_id=0014-rootfs-image-preview
	target_dir="$(field generation_root)/$generation_id"
	target_image="$target_dir/rootfs.squashfs"
	target_manifest="$target_dir/manifest.json"
	target_activation="$target_dir/activation.plan"
	exclusions=$(mksquashfs_exclusions)
	echo "plan=rootfs-image-build"
	echo "mode=dry-run"
	echo "would_create_rootfs_image=false"
	echo "would_create_generation=false"
	echo "would_create_target_dir=false"
	echo "would_mount_filesystems=false"
	echo "would_run_mksquashfs=false"
	echo "would_rebuild_initramfs=false"
	echo "would_switch_current=false"
	echo "would_change_bootloader=false"
	echo "source_root=$(field source_root)"
	echo "target_generation_id=$generation_id"
	echo "target_generation_dir=$target_dir"
	echo "target_image=$target_image"
	echo "target_manifest=$target_manifest"
	echo "target_activation=$target_activation"
	echo "format=$(field format)"
	echo "compression=zstd"
	echo "builder=$(command -v mksquashfs 2>/dev/null || echo missing)"
	echo "unsquashfs=$(command -v unsquashfs 2>/dev/null || echo missing)"
	echo "mksquashfs_command=mksquashfs / $target_image -comp zstd -noappend -wildcards -e$exclusions"
	echo "file_manifest_mode=dry-run-planned"
	echo "file_manifest_future=$target_manifest"
	echo "activation_policy=$(field activation_policy)"
	echo "rollback_policy=$(field rollback_policy)"
	echo "current_target=$(readlink /System/Current 2>/dev/null || true)"
	echo "kernel_profile=$(field kernel_profile)"
	echo "toolkit_root=$(field toolkit_root)"
	echo "runtime_libraries=$(field runtime_libraries)"
	echo "generation_profile=$(field generation_profile)"
	echo "service_profile=$(field service_profile)"
	echo "network_profile=$(field network_profile)"
	echo "remote_profile=$(field remote_profile)"
	input_size_report
	exclusions
	if command -v mksquashfs >/dev/null 2>&1; then
		echo "builder_ready=true"
	else
		echo "builder_ready=false"
	fi
	echo "dry_run_result=plan-generated"
	echo "buildable_now=false"
	echo "build_blocker=actual image creation and activation/switch/rollback not implemented"
}

first_file_exclusions() {
	generation_id=$1
	fields exclude | awk -v generation_id="$generation_id" '
		{
			path = $0
			sub("^/", "", path)
			if (path != "") {
				print path
			}
		}
		END {
			print "System/Generations/" generation_id
		}
	'
}

write_first_file_manifest() {
	generation_id=$1
	target_dir=$2
	target_image=$3
	current_target=$4
	sha=$(sha256sum "$target_image" 2>/dev/null | awk '{ print $1 }')
	size=$(wc -c < "$target_image" 2>/dev/null | awk '{ print $1 }')
	cat > "$target_dir/manifest.json" <<EOF
{
  "id": "$generation_id",
  "type": "rootfs-image-first-file",
  "status": "non-activating",
  "rootfs": "rootfs.squashfs",
  "sha256": "$sha",
  "size_bytes": $size,
  "source_root": "/",
  "format": "squashfs",
  "compression": "zstd",
  "created_by": "mixtar-rootfs-image build --first-file",
  "current_at_build": "$current_target",
  "activation": "not-active"
}
EOF
}

write_first_file_activation_plan() {
	target_dir=$1
	cat > "$target_dir/activation.plan" <<EOF
activation=none
reason=first rootfs.squashfs file only
would_switch_current=false
would_rebuild_initramfs=false
would_change_bootloader=false
rollback=preserve-current-generation
EOF
}

build_first_file() {
	generation_id=0015-rootfs-image-first-file
	target_dir="$(field generation_root)/$generation_id"
	target_image="$target_dir/rootfs.squashfs"
	current_target=$(readlink /System/Current 2>/dev/null || true)
	if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
		echo "build --first-file requires root" >&2
		return 1
	fi
	if [ -e "$target_image" ]; then
		if unsquashfs -s "$target_image" > "$target_dir/unsquashfs-summary.txt" 2>&1; then
			write_first_file_manifest "$generation_id" "$target_dir" "$target_image" "$current_target"
			write_first_file_activation_plan "$target_dir"
			echo "build_status=already-present"
			echo "target_generation_dir=$target_dir"
			echo "target_image=$target_image"
			echo "would_activate_generation=false"
			echo "current_target=$current_target"
			return 0
		fi
		echo "target image exists but is not a valid squashfs: $target_image" >&2
		return 1
	fi
	install -d -m 0755 "$target_dir"
	echo "build_status=building"
	echo "target_generation_dir=$target_dir"
	echo "target_image=$target_image"
	echo "would_activate_generation=false"
	echo "current_target=$current_target"
	echo "mksquashfs_command=mksquashfs / $target_image -comp zstd -noappend -wildcards -e $(first_file_exclusions "$generation_id" | tr '\n' ' ')"
	first_file_exclusions "$generation_id" > "$target_dir/exclusions.txt"
	input_size_report > "$target_dir/input-size-report.txt"
	mksquashfs / "$target_image" -comp zstd -noappend -wildcards -e $(first_file_exclusions "$generation_id") > "$target_dir/mksquashfs.log" 2>&1
	unsquashfs -s "$target_image" > "$target_dir/unsquashfs-summary.txt" 2>&1
	write_first_file_manifest "$generation_id" "$target_dir" "$target_image" "$current_target"
	write_first_file_activation_plan "$target_dir"
	echo "build_status=created"
	echo "sha256=$(sha256sum "$target_image" | awk '{ print $1 }')"
	echo "size_bytes=$(wc -c < "$target_image" | awk '{ print $1 }')"
	echo "manifest=$target_dir/manifest.json"
	echo "activation_plan=$target_dir/activation.plan"
}

readiness() {
	rc=0
	if command -v mksquashfs >/dev/null 2>&1; then
		echo "builder_ready=true"
	else
		echo "builder_ready=false"
		echo "build_blocker=mksquashfs missing"
		rc=1
	fi
	if [ -d "$(field generation_root)" ]; then
		echo "generation_root_ready=true"
	else
		echo "generation_root_ready=false"
		rc=1
	fi
	if [ -f "$(field kernel_profile)/vmlinuz" ]; then
		echo "kernel_vmlinuz_ready=true"
	else
		echo "kernel_vmlinuz_ready=false"
		rc=1
	fi
	if [ -f "$(field kernel_profile)/initramfs.img" ]; then
		echo "kernel_initramfs_ready=true"
	else
		echo "kernel_initramfs_ready=false"
		rc=1
	fi
	if [ -d "$(field toolkit_root)" ]; then
		echo "toolkit_ready=true"
	else
		echo "toolkit_ready=false"
		rc=1
	fi
	if [ -d "$(field runtime_libraries)" ]; then
		echo "runtime_libraries_ready=true"
	else
		echo "runtime_libraries_ready=false"
		rc=1
	fi
	echo "image_buildable_now=false"
	return "$rc"
}

check() {
	rc=0
	if [ ! -f "$PROFILE" ]; then
		echo "missing profile: $PROFILE" >&2
		return 1
	fi
	for key in name format required_builder source_root generation_root future_output kernel_profile toolkit_root runtime_libraries activation_policy rollback_policy; do
		value=$(field "$key")
		if [ -z "$value" ]; then
			echo "missing profile key: $key" >&2
			rc=1
		fi
	done
	for path in \
		"$(field source_root)" \
		"$(field generation_root)" \
		"$(field kernel_profile)" \
		"$(field kernel_profile)/vmlinuz" \
		"$(field kernel_profile)/initramfs.img" \
		"$(field toolkit_root)" \
		"$(field runtime_libraries)" \
		"$(field generation_profile)" \
		"$(field network_profile)" \
		"$(field remote_profile)"
	do
		if [ ! -e "$path" ]; then
			echo "missing input: $path" >&2
			rc=1
		fi
	done
	exclude_count=$(fields exclude | awk 'END { print NR + 0 }')
	if [ "$exclude_count" -lt 8 ]; then
		echo "too few exclusions: $exclude_count" >&2
		rc=1
	fi
	if [ "$rc" -eq 0 ]; then
		if command -v mksquashfs >/dev/null 2>&1; then
			builder_ready=true
		else
			builder_ready=false
		fi
		echo "ok rootfs-image requirements format=$(field format) builder=$(field required_builder) builder_ready=$builder_ready"
	fi
	return "$rc"
}

command=${1:-}
case "$command" in
	contract)
		contract
		;;
	check)
		check
		;;
	requirements)
		requirements
		;;
	inputs)
		inputs
		;;
	exclusions)
		exclusions
		;;
	plan)
		plan
		;;
	backend)
		backend
		;;
	readiness)
		readiness
		;;
	inspect)
		inspect_image
		;;
	contents-check)
		contents_check
		;;
	mount-plan)
		mount_plan
		;;
	mount-inspect)
		mode=${2:-}
		if [ "$mode" != "--once" ]; then
			usage
			exit 2
		fi
		mount_inspect_once
		;;
	file-manifest)
		file_manifest
		;;
	current-manifest)
		current_manifest
		;;
	diff-current)
		diff_current
		;;
	hash-sample)
		hash_sample
		;;
	switch-readiness)
		switch_readiness
		;;
	switch-plan)
		switch_plan
		;;
	initramfs-handoff-plan)
		initramfs_handoff_plan
		;;
	build)
		mode=${2:-}
		if [ "$mode" != "--dry-run" ]; then
			if [ "$mode" = "--first-file" ]; then
				build_first_file
			else
				usage
				exit 2
			fi
		else
			build_dry_run
		fi
		;;
	*)
		usage
		exit 2
		;;
esac
