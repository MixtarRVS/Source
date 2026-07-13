# MixtarRVS Base Closure Alpine/Bootstrap Dependency Inventory

This is the current dependency boundary after installing the source-only
MixtarRVS userland slice.

Operational rule:

```text
/System/Tools/MixtarRVS/bin is the userland identity.
Alpine remains only as bootstrap/runtime compatibility until each category
below is replaced deliberately.
```

Do not replace `/bin` or `/sbin` with the Mixtar Toolkit until the boot/runtime
items in this report have Mixtar-owned replacements.

generated_utc=2026-06-30T15:02:39Z

[boot-boundary]
fallback=Boot0003 debian
preferred_mixtar=Boot0007 MixtarRVS-RT-RW
legacy_mixtar=Boot0006 MixtarRVS RT
preferred_root=/dev/nvme0n1p3 ext4 rw
preferred_kernel=7.1.2-mixtar-rt
safe_return=BootNext 0003

[authoritative-reports]
tool=/System/SystemTools/mixtar-bootstrap-closure-report
mounted_report=/System/Config/MixtarRVS/bootstrap-closure-report-mounted.txt
live_report=/System/Config/MixtarRVS/bootstrap-closure-report-live.txt
live_report_lines=135

[initramfs-runtime-candidate]
tool=/System/SystemTools/mixtar-initramfs-runtime
source=Server/Rootfs/mixtar-initramfs-runtime.sh
live_check=/System/Config/MixtarRVS/initramfs-runtime-live-check.txt
contract=/System/Config/MixtarRVS/initramfs-runtime.contract
plan=/System/Config/MixtarRVS/initramfs-runtime-plan.txt
handoff_proof=/System/Config/MixtarRVS/initramfs-runtime-handoff-live-proof.txt
handoff_entry=Boot0008 MixtarRVS-RT-HANDOFF
status=pid1-handoff-pass-not-default
early_mount_backend=/bin/mount

[supervisor-pid1-candidate]
tool=/System/SystemTools/mixtar-supervisor
source=Server/Rootfs/mixtar-supervisor.sh
init_shim=/System/SystemTools/init
init_shim_source=Server/Rootfs/mixtar-init-shim.sh
handoff_entry=Boot0009 MixtarRVS-RT-SUPERVISOR
handoff_proof=/System/Config/MixtarRVS/supervisor-pid1-openrc-live-proof.txt
marker=/System/Config/MixtarRVS/supervisor-pid1-latest.txt
check=/System/Config/MixtarRVS/supervisor-pid1-check.txt
status=pid1-openrc-handoff-pass-not-default
backend=/sbin/init OpenRC

[direct-service-status]
tool=/System/SystemTools/mixtar-supervisor direct-status
backend=mixtar-procfs
proof=/System/Config/MixtarRVS/supervisor-direct-status-live-proof.txt
report=/System/Config/MixtarRVS/supervisor-direct-status-live.txt
manifest_check=/System/Config/MixtarRVS/supervisor-check-live.txt
services=dbus,iwd,dhcpcd,sshd
status=pass
remaining_backend=openrc-start-stop-order

[direct-start-dbus-candidate]
tool=/System/SystemTools/mixtar-supervisor direct-start dbus
plan=/System/SystemTools/mixtar-supervisor direct-start-plan dbus
backend=mixtar-direct
proof=/System/Config/MixtarRVS/supervisor-direct-start-dbus-live-proof.txt
plan_report=/System/Config/MixtarRVS/supervisor-direct-start-dbus-plan.txt
live_report=/System/Config/MixtarRVS/supervisor-direct-start-dbus-live.txt
post_status=/System/Config/MixtarRVS/supervisor-direct-status-after-dbus-start.txt
status=no-op-live-pass-and-cold-start-before-openrc-pass
cold_start_entry=Boot000A MixtarRVS-RT-DBUS-COLD
cold_start_cmdline=mixtar.direct_start=dbus
cold_start_proof=/System/Config/MixtarRVS/supervisor-direct-start-dbus-cold-live-proof.txt
pid1_cold_start_report=/System/Config/MixtarRVS/supervisor-pid1-direct-start-dbus.txt
remaining_backend=openrc-default-start-order

[direct-start-iwd-candidate]
tool=/System/SystemTools/mixtar-supervisor direct-start iwd
plan=/System/SystemTools/mixtar-supervisor direct-start-plan iwd
backend=mixtar-direct
entrypoint=/usr/libexec/iwd
pidfile=/run/iwd.pid
dependency=dbus
status=no-op-live-pass-and-cold-start-before-openrc-pass
cold_start_entry=Boot000B MixtarRVS-RT-IWD-COLD
cold_start_cmdline=mixtar.direct_start=dbus,iwd
cold_start_proof=/System/Config/MixtarRVS/supervisor-direct-start-iwd-cold-live-proof.txt
pid1_cold_start_report=/System/Config/MixtarRVS/supervisor-pid1-direct-start-iwd.txt
remaining_backend=openrc-dhcpcd-sshd-start-order

[mixtar-userland]
path=/System/Tools/MixtarRVS/bin
tool_count=157
manifest_tools=157
current_link=MixtarRVS

[bootstrap-compatibility-paths]
/bin -> Compatibility/POSIX/Alpine/3.24/bin
/sbin -> Compatibility/POSIX/Alpine/3.24/sbin
/lib -> directory-or-file
/usr/bin -> directory-or-file
/usr/sbin -> directory-or-file
/usr/lib -> directory-or-file
/etc -> directory-or-file
/run -> directory-or-file
/dev -> directory-or-file
/proc -> directory-or-file
/sys -> directory-or-file

[openrc-alpine-services]
dbus -> /etc/init.d/dbus
dhcpcd -> /etc/init.d/dhcpcd
iwd -> /etc/init.d/iwd
mixtar-boot-profiler -> /etc/init.d/mixtar-boot-profiler
mixtar-firstboot-report -> /etc/init.d/mixtar-firstboot-report
mixtar-return-debian-once -> /etc/init.d/mixtar-return-debian-once
mixtar-ssh-watchdog -> ../../init.d/mixtar-ssh-watchdog
sshd -> /etc/init.d/sshd

[critical-bootstrap-commands]
sh /bin/sh link=/bin/busybox
init /sbin/init link=/bin/busybox
mount /bin/mount link=/bin/busybox
mount /sbin/mount link=/bin/busybox
umount /bin/umount link=/bin/busybox
umount /sbin/umount link=/bin/busybox
mdev /sbin/mdev link=/bin/busybox
modprobe /sbin/modprobe link=/bin/busybox
depmod /sbin/depmod link=/bin/busybox
ifconfig /sbin/ifconfig link=/bin/busybox
ip /sbin/ip link=/bin/busybox
route /sbin/route link=/bin/busybox
rc-service /sbin/rc-service file
rc-status /bin/rc-status file
rc-update /sbin/rc-update file
openrc /sbin/openrc file
apk /sbin/apk file
sshd /usr/sbin/sshd file
iwd /usr/libexec/iwd file
dhcpcd /sbin/dhcpcd file
dbus-daemon /usr/bin/dbus-daemon file

[mixtar-source-tools-sample]
echo
cat
pwd
true
false
mkdir
rmdir
cp
ls
mv
rm
domainname
hostname
realpath
sleep
sync
chmod
test
env
dirname
basename
head
tee
touch
readlink
uname
id
date
uniq
wc
ln
cut
sed
arch
printenv
yes
tty
rev
seq
mktemp
