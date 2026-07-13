
## 0019 - rootfs image content hash sample and switch readiness

Status: verified on ThinkPad.

This stage added a non-activating content hash sample and switch-readiness report for the first rootfs image.

Artifacts on target:

```text
/System/Base/Closure/0019-rootfs-image-content-hash-sample-and-switch-readiness/
  manifest.json
  stage-rootfs-image-content-hash-sample-and-switch-readiness.sh
  mixtar-rootfs-image.sh
  hash-sample.txt
  switch-readiness.txt
  hash-and-switch-summary.txt
  rootfs-image-content-hash-sample-and-switch-readiness-status.txt
```

Observed result:

```text
status=verified
hash_sample_status=generated
hash_sample_count=13
hash_match_count=11
hash_mismatch_count=1
current_target=Generations/0002-alpine-openrc-zsh
mount_after=absent
```

Switch-readiness result:

```text
rootfs_image_ready=true
generation_manifest_ready=true
activation_plan_present=true
activation_plan_is_non_activating=true
path_diff_ready=true
image_only_count=0
current_only_count=44
contents_check_ready=true
future_switch_ready=false
would_switch_current=false
would_change_bootloader=false
would_rebuild_initramfs=false
```

The only sampled content mismatch is expected:

```text
sample=sbin/mixtar-rootfs-image
reason=the rootfs image was created at stage 0015, then the live builder tool was extended in later stages
```

No activation was performed. `/System/Current` still points to:

```text
Generations/0002-alpine-openrc-zsh
```

The next stage should create a switch plan without activation. The blockers remain:

```text
initramfs image-root handoff
bootloader entry
rollback policy
garbage collection policy
```

## 0020 - switch plan without activation

Status: verified on ThinkPad.

This stage added a concrete switch plan for the first rootfs image without activating it.

Artifacts on target:

```text
/System/Base/Closure/0020-switch-plan-no-activation/
  manifest.json
  stage-switch-plan-no-activation.sh
  mixtar-rootfs-image.sh
  switch-plan.txt
  switch-readiness.txt
  switch-plan-summary.txt
  switch-plan-no-activation-status.txt
```

Observed result:

```text
status=verified
switch_plan_status=generated
rootfs_image_ready=true
rootfs_size_bytes=783585280
rootfs_sha256=7f48825e78c3cdd47f9bbe9ce29ad26c1cde6bde5b35cf4b5ce0e39a1355a372
current_target=Generations/0002-alpine-openrc-zsh
target_current=Generations/0015-rootfs-image-first-file
activation_allowed=false
future_switch_ready=false
would_switch_current=false
would_change_bootloader=false
would_rebuild_initramfs=false
next_required_stage=0021-initramfs-image-root-handoff-plan
mount_after=absent
```

The generated plan says:

```text
fallback_generation=Generations/0002-alpine-openrc-zsh
previous_generation_preserved=true
would_write_current_link=false
would_write_boot_entry=false
would_mount_rootfs=false
would_delete_previous=false
```

Required before activation:

```text
initramfs-image-root-handoff
bootloader-fallback-entry
rollback-policy
garbage-collection-policy
```

No activation was performed. `/System/Current` still points to:

```text
Generations/0002-alpine-openrc-zsh
```

The rootfs image inspection mountpoint is unmounted.

## 0021 - initramfs image-root handoff plan

Status: verified on ThinkPad.

This stage added a non-activating initramfs handoff contract for booting the first `rootfs.squashfs` image.

Artifacts on target:

```text
/System/Base/Closure/0021-initramfs-image-root-handoff-plan/
  manifest.json
  stage-initramfs-image-root-handoff-plan.sh
  mixtar-rootfs-image.sh
  initramfs-handoff-plan.txt
  switch-plan.txt
  initramfs-handoff-summary.txt
  initramfs-image-root-handoff-plan-status.txt
```

Observed result:

```text
status=verified
initramfs_handoff_plan_status=generated
rootfs_image_ready=true
rootfs_size_bytes=783585280
rootfs_sha256=7f48825e78c3cdd47f9bbe9ce29ad26c1cde6bde5b35cf4b5ce0e39a1355a372
kernel_profile_current=Profiles/rt-7.1.2-mixtar-rt
kernel_vmlinuz_ready=true
kernel_initramfs_ready=true
kernel_modules_ready=true
kernel_squashfs_ready=true
current_boot_root_mode=block-root-ext4
planned_boot_root_mode=image-root-squashfs-readonly-plus-overlay
planned_rootfs_path=/System/Current/rootfs.squashfs
activation_allowed=false
future_handoff_ready=false
would_rebuild_initramfs=false
would_write_initramfs=false
would_change_bootloader=false
would_switch_current=false
next_required_stage=0022-initramfs-handoff-prototype-no-install
current_target=Generations/0002-alpine-openrc-zsh
mount_after=absent
```

Kernel/initramfs artifacts observed:

```text
kernel_vmlinuz_ready_size_bytes=12300800
kernel_vmlinuz_ready_sha256=76a12a0720859ae4b40973f94215a0ceeec0c5579092bd699985f0416ce39b3c
kernel_initramfs_ready_size_bytes=26505153
kernel_initramfs_ready_sha256=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
```

Current boot mode is still block-root ext4:

```text
root=UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c
rootfstype=ext4
rootflags=ro
modules=nvme,ext4,jbd2,mbcache
```

Planned image-root handoff model:

```text
/MixtarBase     # persistent base storage mounted read-only
/MixtarImage    # rootfs.squashfs mounted read-only
/MixtarOverlay  # tmpfs upper/work overlay state
/MixtarRoot     # final root passed to switch_root
```

Required initramfs features:

```text
mount-devtmpfs
mount-procfs
mount-sysfs
mount-base-root-readonly
resolve-system-current
mount-squashfs-image
create-tmpfs-overlay
validate-target-init
switch-root
fallback-to-block-root
```

Important blocker found:

```text
kernel_squashfs_ready=true
kernel_overlay_ready=false
```

So the next stage must prototype the initramfs handoff without installing it, and it must handle overlay availability explicitly.

No activation was performed. `/System/Current` still points to:

```text
Generations/0002-alpine-openrc-zsh
```

The rootfs image inspection mountpoint is unmounted.

## 0022 - initramfs handoff prototype, no install

Status: verified on ThinkPad.

This stage created a concrete initramfs handoff prototype script without installing it into the active initramfs.

Artifacts on target:

```text
/System/Base/Closure/0022-initramfs-handoff-prototype-no-install/
  manifest.json
  stage-initramfs-handoff-prototype-no-install.sh
  mixtar-initramfs-handoff-prototype.sh
  contract.txt
  plan.txt
  check-live.txt
  simulate.txt
  initramfs-handoff-prototype-summary.txt
  initramfs-handoff-prototype-no-install-status.txt

/System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
```

Observed result:

```text
status=verified
initramfs_handoff_prototype_status=generated
prototype_no_install=true
executes_switch_root=false
rootfs_image_ready=true
kernel_squashfs_ready=true
kernel_overlay_ready=false
overlay_policy=overlay-unavailable-prototype-must-fallback-or-readonly
switch_root_tool=/sbin/switch_root
check_live_result=ok
simulation_result=generated
simulation_switch_root_performed=false
initramfs_hash_before=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
initramfs_hash_after=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
current_before=Generations/0002-alpine-openrc-zsh
current_after=Generations/0002-alpine-openrc-zsh
mount_after=absent
next_required_stage=0023-initramfs-builder-input-closure
```

Prototype contract:

```text
prototype_no_install=true
executes_switch_root=false
mounts_rootfs_as_root=false
writes_initramfs=false
writes_bootloader=false
switches_system_current=false
deletes_fallback=false
```

Prototype planned sequence:

```text
step01=mount devtmpfs on /dev
step02=mount proc on /proc
step03=mount sysfs on /sys
step04=mount base block root read-only at /MixtarBase
step05=resolve /System/Current/rootfs.squashfs from base storage
step06=mount squashfs image read-only at /MixtarImage
step07=if overlay is available, create tmpfs upper and work dirs
step08=if overlay is available, mount overlay at /MixtarRoot
step09=if overlay is unavailable, either use read-only image root or fallback according to policy
step10=validate /System/SystemTools/init or /sbin/init exists under new root
step11=switch_root to validated new root
```

Live readiness:

```text
rootfs_image_ready=true
kernel_vmlinuz_ready=true
kernel_initramfs_ready=true
kernel_modules_ready=true
kernel_squashfs_ready=true
kernel_overlay_ready=false
overlay_module_present=false
squashfs_module_present=false
loop_module_present=false
```

The active initramfs was not changed. `/System/Current` still points to:

```text
Generations/0002-alpine-openrc-zsh
```

The next stage should define the input closure needed to build an initramfs containing this prototype and the required tools/modules.

## 0023 - initramfs builder input closure

Status: verified on ThinkPad.

This stage added a non-boot input closure tool for the future MixtarRVS initramfs builder. It does not build or install an initramfs.

Artifacts on target:

```text
/System/Base/Closure/0023-initramfs-builder-input-closure/
  manifest.json
  stage-initramfs-builder-input-closure.sh
  mixtar-initramfs-input-closure.sh
  contract.txt
  tools.txt
  libraries.txt
  modules.txt
  mounts.txt
  report.txt
  initramfs-input-closure-summary.txt
  initramfs-builder-input-closure-status.txt

/System/Initramfs/Prototypes/mixtar-initramfs-input-closure.sh
```

Observed result:

```text
status=verified
initramfs_input_closure_status=generated
builds_initramfs=false
writes_initramfs=false
required_tools_missing=0
required_libraries_missing=0
required_modules_missing=1
overlay_state=missing
rootfs_image_ready=true
handoff_prototype_ready=true
initramfs_build_inputs_ready=false
activation_allowed=false
initramfs_hash_before=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
initramfs_hash_after=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
current_before=Generations/0002-alpine-openrc-zsh
current_after=Generations/0002-alpine-openrc-zsh
mount_after=absent
next_required_stage=0024-overlay-support-decision
```

Required tools are present:

```text
sh
mount
umount
switch_root
modprobe
insmod
blkid
readlink
mkdir
cat
grep
awk
sed
sha256sum
find
```

Dynamic library closure is present:

```text
/lib/ld-musl-x86_64.so.1
/usr/lib/libblkid.so.1
/usr/lib/libcrypto.so.3
/usr/lib/libeconf.so.0
/usr/lib/liblzma.so.5
/usr/lib/libmount.so.1
/usr/lib/libz.so.1
/usr/lib/libzstd.so.1
```

Kernel/module closure after sysfs-aware classification:

```text
module=squashfs state=available_or_builtin
module=overlay state=missing
module=loop state=sys-module-present
module=ext4 state=available_or_builtin
module=nvme state=sys-module-present
module=jbd2 state=sys-module-present
module=mbcache state=sys-module-present
required_modules_missing=1
```

Mount filesystem readiness:

```text
mount_fs=devtmpfs state=available
mount_fs=proc state=available
mount_fs=sysfs state=available
mount_fs=squashfs state=available
mount_fs=overlay state=missing
```

Conclusion:

```text
Tools: ready.
Libraries: ready.
Rootfs image: ready.
Handoff prototype: ready.
Current blocker: overlay support is missing or not exposed in the current kernel profile.
Activation: still disallowed.
```

No boot state was modified. `/System/Current` still points to:

```text
Generations/0002-alpine-openrc-zsh
```

The next stage should decide how MixtarRVS handles overlay support:

```text
0024-overlay-support-decision
```

## 0024 - overlay support decision

Status: verified on ThinkPad.

This stage resolved the overlay blocker from stage 0023. Overlay is not built into the running filesystem list, but the kernel profile has it available as a module.

Artifacts on target:

```text
/System/Base/Closure/0024-overlay-support-decision/
  manifest.json
  stage-overlay-support-decision.sh
  mixtar-overlay-support-decision.sh
  contract.txt
  probe.txt
  decision.txt
  overlay-support-decision-summary.txt
  overlay-support-decision-status.txt

/System/Initramfs/Prototypes/mixtar-overlay-support-decision.sh
```

Observed result:

```text
status=verified
overlay_support_decision_status=generated
config_overlay_fs=m
overlay_module_file_ready=true
overlay_module_path=/lib/modules/7.1.2-mixtar-rt/kernel/fs/overlayfs/overlay.ko.xz
overlay_support_state=available-as-module
kernel_rebuild_required=false
initramfs_must_include_overlay_module=true
primary_boot_policy=squashfs-readonly-plus-writable-overlay
readonly_image_boot_policy=emergency-or-diagnostic-only
activation_allowed=false
next_required_stage=0025-initramfs-module-closure-overlay
initramfs_hash_before=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
initramfs_hash_after=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
current_before=Generations/0002-alpine-openrc-zsh
current_after=Generations/0002-alpine-openrc-zsh
mount_after=absent
```

Overlay probe:

```text
CONFIG_OVERLAY_FS=m
overlay_filesystem_loaded=false
overlay_sys_module_loaded=false
overlay_module_size_bytes=85592
overlay_module_sha256=589ec0285726c0315c0220a0ae0288795b775a41fb9299ccc4e57f29fea752aa
modprobe_dryrun_result=ok
modprobe_dryrun=insmod /lib/modules/7.1.2-mixtar-rt/kernel/fs/overlayfs/overlay.ko.xz
```

Decision:

```text
Kernel rebuild is not required.
The primary MixtarRVS image-root boot policy stays squashfs read-only base plus writable overlay.
Read-only image boot is allowed only as emergency/diagnostic policy, not as the normal target.
The future initramfs must include overlay.ko.xz or equivalent module access.
```

No module was loaded during this stage:

```text
overlay_proc=missing
overlay_sys_module=missing
```

No boot state was modified. `/System/Current` still points to:

```text
Generations/0002-alpine-openrc-zsh
```

The next stage is:

```text
0025-initramfs-module-closure-overlay
```

## 0025 - initramfs module closure: overlay

Status: verified on ThinkPad.

This stage materialized the overlay module closure for the future initramfs candidate. It does not load the module and does not build or install an initramfs.

Artifacts on target:

```text
/System/Base/Closure/0025-initramfs-module-closure-overlay/
  manifest.json
  stage-initramfs-module-closure-overlay.sh
  mixtar-initramfs-module-closure-overlay.sh
  contract.txt
  probe.txt
  plan.txt
  stage-copy.txt
  verify.txt
  report.txt
  initramfs-module-closure-overlay-summary.txt
  initramfs-module-closure-overlay-status.txt

/System/Initramfs/Prototypes/mixtar-initramfs-module-closure-overlay.sh
/System/Initramfs/ModuleClosure/overlay-7.1.2-mixtar-rt/
```

Observed result:

```text
status=verified
overlay_module_closure_status=generated
target_root=/System/Initramfs/ModuleClosure/overlay-7.1.2-mixtar-rt
overlay_source=/lib/modules/7.1.2-mixtar-rt/kernel/fs/overlayfs/overlay.ko.xz
overlay_target=/System/Initramfs/ModuleClosure/overlay-7.1.2-mixtar-rt/lib/modules/7.1.2-mixtar-rt/kernel/fs/overlayfs/overlay.ko.xz
overlay_hash_match=true
module_closure_ready=true
kernel_rebuild_required=false
initramfs_must_include_overlay_module=true
initramfs_candidate_build_ready=true
activation_allowed=false
overlay_loaded_before=false
overlay_loaded_after=false
overlay_sys_module_before=false
overlay_sys_module_after=false
initramfs_hash_before=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
initramfs_hash_after=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
current_before=Generations/0002-alpine-openrc-zsh
current_after=Generations/0002-alpine-openrc-zsh
mount_after=absent
next_required_stage=0026-initramfs-candidate-image-no-install
```

Overlay module hash:

```text
overlay_source_sha256=589ec0285726c0315c0220a0ae0288795b775a41fb9299ccc4e57f29fea752aa
overlay_target_sha256=589ec0285726c0315c0220a0ae0288795b775a41fb9299ccc4e57f29fea752aa
```

Metadata copied and verified:

```text
modules.dep
modules.dep.bin
modules.alias
modules.alias.bin
modules.builtin
modules.order
```

Closure files:

```text
/System/Initramfs/ModuleClosure/overlay-7.1.2-mixtar-rt/lib/modules/7.1.2-mixtar-rt/kernel/fs/overlayfs/overlay.ko.xz
/System/Initramfs/ModuleClosure/overlay-7.1.2-mixtar-rt/lib/modules/7.1.2-mixtar-rt/modules.dep
/System/Initramfs/ModuleClosure/overlay-7.1.2-mixtar-rt/lib/modules/7.1.2-mixtar-rt/modules.dep.bin
/System/Initramfs/ModuleClosure/overlay-7.1.2-mixtar-rt/lib/modules/7.1.2-mixtar-rt/modules.alias
/System/Initramfs/ModuleClosure/overlay-7.1.2-mixtar-rt/lib/modules/7.1.2-mixtar-rt/modules.alias.bin
/System/Initramfs/ModuleClosure/overlay-7.1.2-mixtar-rt/lib/modules/7.1.2-mixtar-rt/modules.builtin
/System/Initramfs/ModuleClosure/overlay-7.1.2-mixtar-rt/lib/modules/7.1.2-mixtar-rt/modules.order
```

No module was loaded:

```text
overlay_proc=missing
overlay_sys_module=missing
```

No boot state was modified. `/System/Current` still points to:

```text
Generations/0002-alpine-openrc-zsh
```

The next stage is:

```text
0026-initramfs-candidate-image-no-install
```

## 0026 - initramfs candidate image, no install

Status: verified on ThinkPad.

This stage built a candidate initramfs image from the active initramfs plus the MixtarRVS handoff prototype and overlay module closure. The candidate was not installed and no boot state was changed.

Artifacts on target:

```text
/System/Base/Closure/0026-initramfs-candidate-image-no-install/
  manifest.json
  stage-initramfs-candidate-image-no-install.sh
  mixtar-initramfs-candidate-builder.sh
  contract.txt
  plan.txt
  build-candidate.txt
  inspect.txt
  verify.txt
  report.txt
  initramfs-candidate-image-summary.txt
  initramfs-candidate-image-no-install-status.txt

/System/Initramfs/Prototypes/mixtar-initramfs-candidate-builder.sh
/System/Initramfs/Candidates/0026-initramfs-candidate-image-no-install/initramfs.img
```

Observed result:

```text
status=verified
candidate_image=/System/Initramfs/Candidates/0026-initramfs-candidate-image-no-install/initramfs.img
candidate_size_bytes=26948286
candidate_sha256=3f3f1148cc2bd5377902ed062c5c3c951b404f939d562a8d99bfcc6559caf2af
active_sha256_before=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
active_sha256_after=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
candidate_gzip_test=ok
candidate_cpio_list=ok
candidate_entry_count=750
candidate_differs_from_active=true
candidate_ready=true
activation_allowed=false
overlay_loaded_after=false
overlay_sys_module_after=false
current_before=Generations/0002-alpine-openrc-zsh
current_after=Generations/0002-alpine-openrc-zsh
mount_after=absent
next_required_stage=0027-initramfs-candidate-diff-and-boot-entry-plan
```

Candidate format:

```text
gzip compressed cpio newc image
```

Candidate contains required Mixtar additions:

```text
usr/lib/modules/7.1.2-mixtar-rt/kernel/fs/overlayfs/overlay.ko.xz
System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
usr/bin/mixtar-initramfs-handoff
etc/mixtar-initramfs-candidate
```

The original active initramfs was not changed:

```text
/System/Kernel/Current/initramfs.img
sha256=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
```

No module was loaded:

```text
overlay_proc=missing
overlay_sys_module=missing
```

No boot state was modified. `/System/Current` still points to:

```text
Generations/0002-alpine-openrc-zsh
```

The next stage is:

```text
0027-initramfs-candidate-diff-and-boot-entry-plan
```

## 0027 - initramfs candidate diff and boot entry plan

Status: verified on ThinkPad.

This stage compared the candidate initramfs against the active initramfs and generated a non-mutating boot entry plan. No ESP copy, EFI boot entry creation, BootOrder change, or BootNext change was performed.

Artifacts on target:

```text
/System/Base/Closure/0027-initramfs-candidate-diff-and-boot-entry-plan/
  manifest.json
  stage-initramfs-candidate-diff-and-boot-entry-plan.sh
  mixtar-initramfs-candidate-boot-plan.sh
  contract.txt
  diff.txt
  boot-probe.txt
  boot-plan.txt
  report.txt
  initramfs-candidate-boot-plan-summary.txt
  initramfs-candidate-diff-and-boot-entry-plan-status.txt

/System/Initramfs/Prototypes/mixtar-initramfs-candidate-boot-plan.sh
```

Observed result:

```text
status=verified
active_sha256=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
candidate_sha256=3f3f1148cc2bd5377902ed062c5c3c951b404f939d562a8d99bfcc6559caf2af
candidate_only_count=6
active_only_count=0
boot_current=0006
current_initrd_arg=\EFI\mixtarrvs-rt\initrd.img
esp_mounted=false
planned_candidate_initrd_esp_path=\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0026.img
would_copy_candidate_to_esp=false
would_create_boot_entry=false
would_change_boot_order=false
would_set_boot_next=false
activation_allowed=false
boot_entry_ready=false
active_initramfs_hash_before=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
active_initramfs_hash_after=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
current_before=Generations/0002-alpine-openrc-zsh
current_after=Generations/0002-alpine-openrc-zsh
mount_after=absent
next_required_stage=0028-initramfs-candidate-init-handoff-wiring-no-install
```

Candidate-only initramfs entries:

```text
System
System/Initramfs
System/Initramfs/Prototypes
System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
etc/mixtar-initramfs-candidate
usr/bin/mixtar-initramfs-handoff
```

Overlay module status from the diff:

```text
candidate_addition=usr/lib/modules/7.1.2-mixtar-rt/kernel/fs/overlayfs/overlay.ko.xz:already-present
```

This corrects the earlier interpretation: the active initramfs already contains `overlay.ko.xz`. The blocker is not module presence in the archive; the blocker is that the active initramfs `/init` does not delegate to the Mixtar handoff yet.

Current boot state:

```text
BootCurrent=0006
current_initrd_arg=\EFI\mixtarrvs-rt\initrd.img
current_root_arg=UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c
current_rootfstype=ext4
current_rootflags=ro
current_modules=nvme,ext4,jbd2,mbcache
current_mixtar_profile=rt-7.1.2-mixtar-rt
```

Planned future candidate boot entry:

```text
planned_label=MixtarRVS RT Candidate 0026
planned_kernel_esp_path=\\EFI\\mixtarrvs-rt\\vmlinuz.efi
planned_candidate_initrd_esp_path=\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0026.img
planned_copy_source=/System/Initramfs/Candidates/0026-initramfs-candidate-image-no-install/initramfs.img
planned_kernel_args=initrd=\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0026.img root=UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=/System/Current/rootfs.squashfs mixtar.overlay=tmpfs mixtar.fallback=previous
```

Boot entry blockers:

```text
candidate initramfs contains Mixtar handoff prototype but active /init is not wired to delegate to it
ESP mount/copy step is not implemented in this stage
```

Fallback policy:

```text
preserve Boot0006 MixtarRVS RT
preserve current /System/Current
```

No boot state was modified. `BootCurrent` stayed `0006`, active initramfs hash stayed unchanged, and `/System/Current` still points to:

```text
Generations/0002-alpine-openrc-zsh
```

The next stage is:

```text
0028-initramfs-candidate-init-handoff-wiring-no-install
```

## 0028 - initramfs candidate init handoff wiring, no install

Status: verified on ThinkPad.

This stage built a new wired candidate initramfs where `/init` is a Mixtar wrapper and the original Alpine initramfs init is preserved as `/init.alpine`. The wired candidate was not installed and no boot state was changed.

Artifacts on target:

```text
/System/Base/Closure/0028-initramfs-candidate-init-handoff-wiring-no-install/
  manifest.json
  stage-initramfs-candidate-init-handoff-wiring-no-install.sh
  mixtar-initramfs-init-wiring-builder.sh
  mixtar-init-wrapper.sh
  contract.txt
  plan.txt
  build-wired-candidate.txt
  inspect.txt
  verify.txt
  report.txt
  initramfs-init-handoff-wiring-summary.txt
  initramfs-candidate-init-handoff-wiring-no-install-status.txt

/System/Initramfs/Prototypes/mixtar-initramfs-init-wiring-builder.sh
/System/Initramfs/Prototypes/mixtar-init-wrapper.sh
/System/Initramfs/Candidates/0028-initramfs-candidate-init-handoff-wiring-no-install/initramfs.img
```

Observed result:

```text
status=verified
target_image=/System/Initramfs/Candidates/0028-initramfs-candidate-init-handoff-wiring-no-install/initramfs.img
target_size_bytes=26948472
target_sha256=41d02fc3532ee8b7b155df0e040ff27af51f8c10604abefabcbfd125ce5849a6
source_candidate_sha256=3f3f1148cc2bd5377902ed062c5c3c951b404f939d562a8d99bfcc6559caf2af
target_gzip_test=ok
target_cpio_list=ok
wrapper_installed_as_init=true
original_init_preserved=true
wired_candidate_ready=true
boot_test_ready=false
activation_allowed=false
active_initramfs_hash_before=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
active_initramfs_hash_after=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
current_before=Generations/0002-alpine-openrc-zsh
current_after=Generations/0002-alpine-openrc-zsh
mount_after=absent
next_required_stage=0029-initramfs-handoff-boot-command-no-install
```

Wired candidate contains:

```text
/init                         # Mixtar wrapper
/init.alpine                  # preserved original Alpine initramfs init
/usr/bin/mixtar-initramfs-handoff
/System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
/etc/mixtar-initramfs-wired-candidate
```

Hash proof:

```text
wrapper_sha256=7c8b7899c359ef1dd4e5a87eb5acf96b185e03cb91423f670bd8b8539d4283be
target_init_sha256=7c8b7899c359ef1dd4e5a87eb5acf96b185e03cb91423f670bd8b8539d4283be
target_original_init_sha256=ed39cc3fe4db146315f1f877c94fad9fa99a057ed590cf1857ed9fb32912f57a
source_candidate_init_sha256=ed39cc3fe4db146315f1f877c94fad9fa99a057ed590cf1857ed9fb32912f57a
```

Wrapper policy:

```text
No mixtar.rootfs -> exec /init.alpine
mixtar.rootfs present but mixtar.handoff=boot absent -> run handoff simulate, then exec /init.alpine
mixtar.handoff=boot present -> try handoff boot, then fallback to /init.alpine if it fails
```

The current blocker moved forward:

```text
boot_test_ready=false
boot_test_blocker=handoff script still has no real boot command
```

No boot state was modified. Active initramfs hash stayed unchanged and `/System/Current` still points to:

```text
Generations/0002-alpine-openrc-zsh
```

The next stage is:

```text
0029-initramfs-handoff-boot-command-no-install
```

## 0029 - initramfs handoff boot command, no install

Status: verified on ThinkPad.

This stage added a real `boot` command to the Mixtar initramfs handoff tool and built a new candidate initramfs containing it. The boot command was not executed and the candidate was not installed.

Artifacts on target:

```text
/System/Base/Closure/0029-initramfs-handoff-boot-command-no-install/
  manifest.json
  stage-initramfs-handoff-boot-command-no-install.sh
  mixtar-initramfs-handoff-boot-builder.sh
  mixtar-initramfs-handoff-prototype.sh
  contract.txt
  plan.txt
  build-candidate.txt
  inspect.txt
  verify.txt
  report.txt
  initramfs-handoff-boot-command-summary.txt
  initramfs-handoff-boot-command-no-install-status.txt

/System/Initramfs/Prototypes/mixtar-initramfs-handoff-boot-builder.sh
/System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
/System/Initramfs/Candidates/0029-initramfs-handoff-boot-command-no-install/initramfs.img
```

Observed result:

```text
status=verified
target_image=/System/Initramfs/Candidates/0029-initramfs-handoff-boot-command-no-install/initramfs.img
target_size_bytes=26952175
target_sha256=4880325f92e6912b67c2c5003de14907f6cbde5a0bd700392386db0443496bfb
source_candidate_sha256=41d02fc3532ee8b7b155df0e040ff27af51f8c10604abefabcbfd125ce5849a6
handoff_source_sha256=c715919a88f8782afe628d921171b923d5de5bda62ccce5c4a68f1dc89ef5357
target_gzip_test=ok
target_cpio_list=ok
handoff_hash_match=true
boot_command_available=true
boot_executes_switch_root_when_run=true
handoff_boot_candidate_ready=true
boot_entry_ready=false
activation_allowed=false
active_initramfs_hash_before=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
active_initramfs_hash_after=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
current_before=Generations/0002-alpine-openrc-zsh
current_after=Generations/0002-alpine-openrc-zsh
mount_after=absent
next_required_stage=0030-esp-candidate-copy-plan-no-activation
```

Candidate contains:

```text
/init
/init.alpine
usr/bin/mixtar-initramfs-handoff
System/Initramfs/Prototypes/mixtar-initramfs-handoff.sh
etc/mixtar-initramfs-handoff-boot-candidate
```

The handoff contract extracted from the candidate reports:

```text
boot_command_available=true
executes_switch_root_when_boot_command_runs=true
boot_command_requires_mixtar_handoff_boot=true
```

The candidate handoff contains a real boot dispatch and switch-root path:

```text
boot)
exec switch_root "$target_root" "$init_path"
```

Boot command behavior implemented in the handoff:

```text
mount devtmpfs/proc/sysfs
load modules from kernel cmdline plus squashfs/overlay
resolve root=UUID/LABEL/device
mount base root at /MixtarBase
resolve /System/Current/rootfs.squashfs
mount squashfs at /MixtarImage
mount tmpfs-backed overlay at /MixtarRoot
select /System/SystemTools/init or /sbin/init
move runtime mounts
exec switch_root
```

No boot command was executed during this stage. No boot state was modified:

```text
BootCurrent=0006
BootOrder unchanged
active_initramfs unchanged
/System/Current unchanged
overlay not mounted by this stage
```

The next stage is:

```text
0030-esp-candidate-copy-plan-no-activation
```

## 0030 - ESP candidate copy plan, no activation

Status: verified on ThinkPad.

This stage generated a non-mutating plan for copying the boot-capable 0029 candidate initramfs to the ESP and creating a future fallback-preserving EFI test entry. It did not mount the ESP, copy files, create EFI entries, set BootNext, or change BootOrder.

Artifacts on target:

```text
/System/Base/Closure/0030-esp-candidate-copy-plan-no-activation/
  manifest.json
  stage-esp-candidate-copy-plan-no-activation.sh
  mixtar-esp-candidate-copy-plan.sh
  contract.txt
  probe.txt
  plan.txt
  report.txt
  esp-candidate-copy-plan-summary.txt
  esp-candidate-copy-plan-no-activation-status.txt

/System/Initramfs/Prototypes/mixtar-esp-candidate-copy-plan.sh
```

Observed result:

```text
status=verified
boot_current=0006
esp_partuuid=bbd8b85d-f0d0-4262-b930-fd1ae4360165
esp_device=/dev/nvme0n1p1
esp_device_ready=true
esp_fstype=vfat
esp_uuid=F70B-FE60
esp_currently_mounted_before=false
esp_currently_mounted_after=false
candidate_image_ready=true
candidate_size_bytes=26952175
candidate_sha256=4880325f92e6912b67c2c5003de14907f6cbde5a0bd700392386db0443496bfb
planned_copy_target_relative=EFI/mixtarrvs-rt/initrd-mixtar-candidate-0029.img
planned_copy_target_uefi=\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0029.img
would_mount_esp=false
would_copy_candidate_to_esp=false
would_create_boot_entry=false
would_change_boot_order=false
would_set_boot_next=false
activation_allowed=false
copy_plan_ready=true
boot_test_ready=false
active_initramfs_hash_before=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
active_initramfs_hash_after=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
current_before=Generations/0002-alpine-openrc-zsh
current_after=Generations/0002-alpine-openrc-zsh
mount_after=absent
next_required_stage=0031-esp-candidate-copy-no-bootentry
```

Current active boot anchor:

```text
BootCurrent=0006
BootOrder=0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F
active_initrd_arg=\\EFI\\mixtarrvs-rt\\initrd.img
```

Resolved ESP:

```text
device=/dev/nvme0n1p1
filesystem=vfat
uuid=F70B-FE60
partuuid=bbd8b85d-f0d0-4262-b930-fd1ae4360165
```

Planned future copy target:

```text
source=/System/Initramfs/Candidates/0029-initramfs-handoff-boot-command-no-install/initramfs.img
target=EFI/mixtarrvs-rt/initrd-mixtar-candidate-0029.img
uefi_path=\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0029.img
```

Planned future kernel args:

```text
initrd=\\EFI\\mixtarrvs-rt\\initrd-mixtar-candidate-0029.img root=UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=/System/Current/rootfs.squashfs mixtar.overlay=tmpfs mixtar.fallback=previous mixtar.handoff=boot
```

Future steps recorded by the plan:

```text
mount ESP at /System/Runtime/ESP/mixtarrvs-rt-candidate
copy candidate initramfs to EFI/mixtarrvs-rt/initrd-mixtar-candidate-0029.img
sync and verify copied hash
create disabled/test EFI boot entry with label MixtarRVS RT Candidate 0029
set BootNext only for a single test boot after explicit approval
preserve Boot0006 and BootOrder fallback
```

No boot state was modified:

```text
ESP not mounted
candidate not copied to ESP
no EFI entry created
BootOrder unchanged
BootNext not set
active initramfs hash unchanged
/System/Current unchanged
```

The next stage is:

```text
0031-esp-candidate-copy-no-bootentry
```

## 0031 - ESP candidate copy, no boot entry

Status: verified on ThinkPad.

This stage copied the 0029 boot-capable candidate initramfs to the ESP under a unique filename. It did not create an EFI boot entry, change BootOrder, set BootNext, overwrite the active initrd, or switch `/System/Current`.

Artifacts on target:

```text
/System/Base/Closure/0031-esp-candidate-copy-no-bootentry/
  manifest.json
  stage-esp-candidate-copy-no-bootentry.sh
  mixtar-esp-candidate-copy.sh
  contract.txt
  plan.txt
  copy.txt
  verify-copy.txt
  report.txt
  esp-candidate-copy-summary.txt
  esp-candidate-copy-no-bootentry-status.txt
```

ESP target copied:

```text
EFI/mixtarrvs-rt/initrd-mixtar-candidate-0029.img
```

Observed result:

```text
status=verified
copy_status=copied
source_sha256=4880325f92e6912b67c2c5003de14907f6cbde5a0bd700392386db0443496bfb
target_sha256=4880325f92e6912b67c2c5003de14907f6cbde5a0bd700392386db0443496bfb
copy_hash_match=true
source_size_bytes=26952175
target_size_bytes=26952175
esp_mounted_before=false
esp_mounted_after=false
active_initramfs_hash_before=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
active_initramfs_hash_after=7bb00349db1b931f699293531e56541413c77f72b5eabd8e9dcd9ca65fef6483
current_before=Generations/0002-alpine-openrc-zsh
current_after=Generations/0002-alpine-openrc-zsh
mount_after=absent
writes_boot_entry=false
changes_boot_order=false
sets_boot_next=false
activation_allowed=false
next_required_stage=0032-efi-boot-entry-plan-with-bootnext
```

Boot state before and after stayed identical:

```text
BootCurrent: 0006
BootOrder: 0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F
```

The ESP was mounted only temporarily by the copy tool and was unmounted after verification:

```text
esp_mounted_after=false
```

No boot entry exists for the candidate yet. The firmware still boots the existing fallback entry:

```text
Boot0006 MixtarRVS RT
```

The next stage is:

```text
0032-efi-boot-entry-plan-with-bootnext
```

## 0032 - EFI boot entry plan with BootNext, no mutation

Status: verified on ThinkPad.

This stage planned the candidate EFI boot entry for the 0029 boot-capable initramfs and the later one-shot `BootNext` test path. It did not create an EFI entry, change BootOrder, set BootNext, overwrite the active initrd, or reboot the machine.

Artifacts on target:

```text
/System/Base/Closure/0032-efi-boot-entry-plan-with-bootnext/
  manifest.json
  stage-efi-boot-entry-plan-with-bootnext.sh
  mixtar-efi-boot-entry-plan.sh
  contract.txt
  plan.txt
  verify-plan.txt
  efibootmgr-before.txt
  efibootmgr-after.txt
  efi-boot-entry-plan-summary.txt
  report.txt
```

Observed result:

```text
status=verified
boot_current=0006
boot_order=0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F
bootnext_present=false
bootnext=none
candidate_entry_present=false
source_hash_expected=true
esp_hash_expected=true
kernel_on_esp=true
fallback_boot_entry_present=true
esp_mounted_after=false
boot_state_changed=false
writes_boot_entry=false
changes_boot_order=false
sets_boot_next=false
reboots_system=false
```

Planned future command for creating the candidate entry:

```text
efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "MixtarRVS RT Candidate 0029" --loader "\EFI\mixtarrvs-rt\vmlinuz.efi" --unicode "initrd=\EFI\mixtarrvs-rt\initrd-mixtar-candidate-0029.img root=UUID=146d4ab3-3e58-4317-8799-da2f451b9a6c rootfstype=ext4 rootflags=ro modules=nvme,ext4,jbd2,mbcache rootwait ro quiet loglevel=3 threadirqs mixtar.profile=rt-7.1.2-mixtar-rt mixtar.rootfs=/System/Current/rootfs.squashfs mixtar.overlay=tmpfs mixtar.fallback=previous mixtar.handoff=boot"
```

Planned safety follow-up after creating the candidate entry:

```text
efibootmgr --bootorder 0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F
efibootmgr --bootnext <candidate_bootnum>
```

The next stage is:

```text
0033-create-candidate-efi-entry-preserve-bootorder
```

## 0033 - Create candidate EFI entry, preserve BootOrder

Status: verified on ThinkPad.

This stage created a separate EFI entry for the 0029 boot-capable candidate initramfs. It restored the previous BootOrder immediately after creation. It did not set BootNext and did not reboot the machine.

Artifacts on target:

```text
/System/Base/Closure/0033-create-candidate-efi-entry-preserve-bootorder/
  manifest.json
  stage-create-candidate-efi-entry-preserve-bootorder.sh
  mixtar-efi-create-candidate-entry.sh
  contract.txt
  create.txt
  efibootmgr-before.txt
  efibootmgr-after.txt
  create-candidate-efi-entry-summary.txt
  report.txt
```

Observed result:

```text
status=verified
action=created
create_exit=0
restore_exit=0
boot_current=0006
boot_order=0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F
bootnext_present=false
bootnext=none
candidate_bootnum=0007
candidate_entry_present=true
fallback_boot_entry_present=true
boot_order_preserved=true
bootnext_preserved=true
creates_boot_entry=true
sets_boot_next=false
reboots_system=false
```

The new candidate entry is:

```text
Boot0007 MixtarRVS RT Candidate 0029
```

The fallback remains first in BootOrder:

```text
Boot0006 MixtarRVS RT
```

The next stage is intentionally a rebooting stage:

```text
0034-set-bootnext-one-shot-candidate-test
```

That stage should set only:

```text
efibootmgr --bootnext 0007
reboot
```

Expected safety property: if the candidate boot fails or does not persist, firmware should return to normal BootOrder with `Boot0006 MixtarRVS RT` first on the following boot.

## 0034 - BootNext candidate test preflight, no reboot

Status: verified preflight on ThinkPad.

This stage installed the controlled one-shot candidate boot helper and ran only its non-mutating preflight mode. It did not set BootNext and did not reboot the machine.

Artifacts on target:

```text
/System/Base/Closure/0034-set-bootnext-one-shot-candidate-test/
  manifest.json
  stage-bootnext-candidate-test-preflight-no-reboot.sh
  mixtar-efi-bootnext-candidate-test.sh
  contract.txt
  preflight.txt
  efibootmgr-before-preflight.txt
  efibootmgr-after-preflight.txt
  bootnext-candidate-test-preflight-summary.txt
  report.txt
```

Observed preflight result:

```text
status=verified_preflight
preflight_status=ready
ready_to_arm_bootnext=true
boot_current=0006
boot_order=0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F
bootnext_present=false
candidate_entry_present=true
fallback_entry_present=true
boot_state_changed=false
sets_boot_next=false
reboots_system=false
```

Candidate and fallback state:

```text
candidate_bootnum=0007
candidate_entry_present=true
fallback_bootnum=0006
fallback_entry_present=true
```

Commands prepared on target for the actual test boot:

```text
sudo sh /System/Base/Closure/0034-set-bootnext-one-shot-candidate-test/mixtar-efi-bootnext-candidate-test.sh arm
sudo reboot
```

Command prepared for verification after the machine comes back:

```text
sudo sh /System/Base/Closure/0034-set-bootnext-one-shot-candidate-test/mixtar-efi-bootnext-candidate-test.sh postboot
```

Expected successful candidate boot evidence:

```text
BootCurrent=0007
/proc/cmdline contains mixtar.handoff=boot
```

Expected fallback safety property:

```text
BootOrder still starts with Boot0006 MixtarRVS RT.
BootNext is one-shot and should not permanently replace the fallback path.
```

## 0034 - One-shot candidate 0029 boot test result

Status: candidate EFI/initramfs path verified, image-root handoff not achieved.

The one-shot BootNext test booted the candidate entry:

```text
BootCurrent=0007
cmdline_has_candidate_token=true
BootOrder=0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F
BootNext=none
```

The machine returned over SSH, proving the firmware path and candidate initramfs file were usable. However the runtime root was still the block root:

```text
root_mount_source=/dev/nvme0n1p3
/proc/cmdline contains mixtar.handoff=boot
```

Diagnosis from extracted candidate initramfs and kernel logs:

```text
candidate contains one /init wrapper and one /init.alpine fallback
/proc/cmdline contains mixtar.rootfs and mixtar.handoff=boot
no mixtar-init / mixtar-handoff messages appeared in dmesg
kernel continued through Alpine-style Mounting root path
```

Likely cause:

```text
/init wrapper read /proc/cmdline before mounting /proc.
cmdline_value therefore saw no mixtar.rootfs and fell back to /init.alpine.
```

This makes 0034 a useful boot-path proof, not a successful clean-root/image-root proof.

## 0035 - Initramfs wrapper procfs fix, no install

Status: verified on ThinkPad.

This stage rebuilt the 0029 candidate into a new 0035 candidate with a fixed `/init` wrapper. The wrapper now mounts `/dev`, `/proc`, and `/sys` before parsing `/proc/cmdline`, and fallback to `/init.alpine` no longer passes the fallback reason as an init argument.

Artifacts on target:

```text
/System/Base/Closure/0035-initramfs-wrapper-procfix-no-install/
  manifest.json
  contract.txt
  plan.txt
  build-candidate.txt
  inspect.txt
  verify.txt
  report-builder.txt
  initramfs-wrapper-procfix-summary.txt
  report.txt

/System/Initramfs/Candidates/0035-initramfs-wrapper-procfix-no-install/initramfs.img
```

Observed result:

```text
status=verified
source_candidate_sha256=4880325f92e6912b67c2c5003de14907f6cbde5a0bd700392386db0443496bfb
wrapper_source_sha256=be567cda0559b6efcc83a643b07fbfc7f4bf8a75a5e69a5d7d09ba49e7b750d1
target_image=/System/Initramfs/Candidates/0035-initramfs-wrapper-procfix-no-install/initramfs.img
target_size_bytes=26949680
target_sha256=2060cdc9e2d61928687a82ddb4dc8d4cc7e84be833e746953dabe392e182a835
verify_result=ok
candidate_ready=true
wrapper_mounts_before_cmdline_parse=true
fallback_exec_has_no_error_argument=true
installs_candidate_initramfs=false
copies_candidate_to_esp=false
creates_boot_entry=false
sets_boot_next=false
reboots_system=false
```

## 0036 - Copy procfix candidate to ESP and create inactive EFI entry

Status: verified on ThinkPad.

This stage copied the 0035 procfix candidate to the ESP and created a separate EFI entry for it. It restored the previous BootOrder immediately. It did not set BootNext and did not reboot the machine.

Artifacts on target:

```text
/System/Base/Closure/0036-copy-procfix-candidate-to-esp-no-active-switch/
  manifest.json
  contract.txt
  plan.txt
  apply.txt
  efibootmgr-before.txt
  efibootmgr-after.txt
  procfix-candidate-esp-efi-summary.txt
  report.txt
```

Observed result:

```text
status=verified
entry_action=created
boot_current=0006
boot_order=0006,0003,0004,0005,0017,0018,0019,001A,001B,001C,001D,001E,001F
bootnext_present=false
source_sha256=2060cdc9e2d61928687a82ddb4dc8d4cc7e84be833e746953dabe392e182a835
target_sha256=2060cdc9e2d61928687a82ddb4dc8d4cc7e84be833e746953dabe392e182a835
copy_hash_match=true
candidate_bootnum=0008
boot_order_preserved=true
bootnext_preserved=true
fallback_boot_entry_present=true
esp_mounted_after=false
copies_candidate_to_esp=true
creates_boot_entry=true
sets_boot_next=false
reboots_system=false
```

The new procfix candidate entry is:

```text
Boot0008 MixtarRVS RT Candidate 0035
```

The fallback remains first:

```text
Boot0006 MixtarRVS RT
```

Next test stage:

```text
0037-set-bootnext-one-shot-procfix-candidate-test
```

## 0053 - Boot000F openrc-init candidate test

Date: 2026-06-30

Result: partial boot, image-root handoff not achieved.

Observed:
- BootCurrent: 000F
- BootOrder preserved with Boot0006 first fallback.
- Kernel command line used initrd-mixtar-candidate-0052.img.
- rdinit=/mixtar-init executed.
- mixtar-init wrapper started.
- Mixtar handoff loaded nvme, ext4, jbd2, mbcache, squashfs, and overlay.
- mdev scan completed.
- Base root /dev/nvme0n1p3 mounted.
- rootfs image /System/Generations/0015-rootfs-image-first-file/rootfs.squashfs mounted.
- handoff reached switch_root.

Failure:
- handoff log still reports: switch_root target=/MixtarRoot init=/sbin/init
- final / mount after boot is still /dev/nvme0n1p3 ext4 rw, not overlay/squashfs.
- /System/Current remains Generations/0002-alpine-openrc-zsh.

Conclusion:
- Candidate 0052 proves the custom initramfs path reaches rootfs image mount.
- The next blocker is the final init/handoff path: /sbin/init in the image resolves to BusyBox behavior, which remounts/continues the block-device Alpine-style root instead of keeping MixtarRoot as the active root.
- Next candidate must force switch_root to /sbin/openrc-init or provide a Mixtar-owned init handoff inside the image-root.

## 0057-0064 - image-root handoff narrowing

Date: 2026-06-30

Summary:
- 0057 built /System/Generations/0017-rootfs-image-openrc-root-noop/rootfs.squashfs from 0016.
- 0017 keeps the fstab block-root entry disabled and replaces /etc/init.d/root with a Mixtar no-op service.
- 0058 created Boot0025 for rootfs 0017 with initramfs 0052.
- 0059 tested Boot0025: system still returned to /dev/nvme0n1p3 as /.
- Inspection showed initramfs 0052 had BusyBox with switch_root applet, but no switch_root applet symlink in PATH.
- 0060 built initramfs candidate with /usr/bin/busybox switch_root and switch_root applet symlinks, then created Boot0026.
- 0061 tested Boot0026: still returned to /dev/nvme0n1p3 as /.
- 0062 built readonly image-root candidate:
  - /System/Generations/0018-rootfs-image-readonly-base-preserve/rootfs.squashfs
  - initramfs candidate 0062
  - Boot0027
  - mixtar.overlay=readonly
  - /MixtarBase moved into /MixtarImage/System/Runtime/initramfs/base before switch_root
- 0063 tested Boot0027: handoff moved base root into readonly target and attempted switch_root, but handoff ran as a child process under /mixtar-init, so switch_root failed and fallback returned to /dev/nvme0n1p3.
- 0064 built PID1 handoff candidate:
  - /mixtar-init now execs /usr/bin/mixtar-initramfs-handoff boot
  - handoff boot path has fallback to /init if boot_command fails
  - Boot0028 created with rootfs 0018 and initramfs 0064

0064 test result:
- BootNext=0028 was set.
- BootOrder remained preserved with Boot0006 first.
- SSH did not return within 420 seconds.

Conclusion:
- The root cause before 0064 was confirmed: switch_root was being executed outside PID 1.
- 0064 likely progressed past the previous fallback path, but the readonly image-root did not bring SSH back or boot completion was blocked.
- Next step after manual fallback reboot: inspect console-visible failure if available, or boot back into Boot0006 and collect previous-boot logs if persisted. If no logs persisted, create a 0065 diagnostic candidate that writes switch_root/openrc progress to the preserved base mount before exec.

## 0065 - diagnostic image-root stage prepared locally

Date: 2026-06-30

Status: prepared locally, not deployed.

Reason:
- Boot0028 / 0064 did not return over SSH within 420 seconds.
- The laptop is currently not reachable at 192.168.99.110:22.
- BootOrder was previously preserved with Boot0006 first, so a manual reboot should return to the safe fallback.

Prepared artifact:
- Server/Rootfs/scripts/stage-0065-diagnostic-image-root.sh

Purpose:
- After fallback SSH returns, this script builds a diagnostic readonly image-root candidate.
- It creates rootfs generation 0019 with a diagnostic /sbin/init wrapper.
- If switch_root succeeds, the diagnostic init writes persistent logs to the preserved base root:
  /System/Base/Closure/0065-after-switch-root.log
  /System/Base/Closure/0065-openrc-report.log
- It also patches initramfs handoff logging so initramfs progress is persisted to:
  /System/Base/Closure/0065-initramfs-handoff.log
- It creates a new UEFI candidate without changing BootOrder and without rebooting.

Next required external action:
- Manually reboot the ThinkPad so it falls back to Boot0006 MixtarRVS RT.
- Then rerun SSH reachability and deploy 0065.

## 0065 - deploy still waiting for fallback SSH

Date: 2026-06-30

Status: not deployed.

Probe result:
- SSH to vxz@192.168.99.110 timed out again.
- No remote mutation was performed.

Required next step:
- Manually reboot the ThinkPad so firmware falls back to Boot0006 MixtarRVS RT.
- After SSH returns, deploy Server/Rootfs/scripts/stage-0065-diagnostic-image-root.sh.

## 0065 - third SSH timeout, external reboot required

Date: 2026-06-30

Status: blocked by unreachable ThinkPad.

Probe result:
- Third consecutive goal-turn SSH probe to vxz@192.168.99.110 timed out.
- No remote mutation was performed.
- Prepared diagnostic stage remains local and ready:
  Server/Rootfs/scripts/stage-0065-diagnostic-image-root.sh

Blocking condition:
- After Boot0028 / 0064, the laptop has not returned to SSH.
- Further safe deployment requires the ThinkPad to be manually rebooted into fallback Boot0006 MixtarRVS RT, or local console access to inspect Boot0028.

Resume condition:
- Reboot the ThinkPad manually.
- Confirm SSH at 192.168.99.110 returns.
- Then deploy 0065 and inspect persistent logs under /System/Base/Closure.
