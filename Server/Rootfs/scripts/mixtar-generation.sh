#!/System/Tools/Current/bin/sh
set -u

PROFILE=${MIXTAR_GENERATION_PROFILE:-/System/Config/Generation/current.generation}
APK=${MIXTAR_APK:-/sbin/apk}
WORLD=${MIXTAR_APK_WORLD:-/etc/apk/world}
REPOS=${MIXTAR_APK_REPOS:-/etc/apk/repositories}
TOOLS=${MIXTAR_TOOLS:-/System/Tools/Current/bin}
CURRENT=${MIXTAR_CURRENT:-/System/Current}
GENERATIONS=${MIXTAR_GENERATIONS:-/System/Generations}

usage() {
	cat >&2 <<EOF
usage: mixtar-generation <command>

commands:
  contract
  check
  status
  profile
  world
  repos
  packages
  backend
  closure
  build --dry-run
EOF
}

field() {
	key=$1
	awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$PROFILE"
}

count_lines() {
	awk 'END { print NR + 0 }'
}

toolkit_count() {
	ls -1 "$TOOLS" 2>/dev/null | count_lines
}

package_count() {
	"$APK" info 2>/dev/null | count_lines
}

world_count() {
	awk 'NF > 0 { count++ } END { print count + 0 }' "$WORLD" 2>/dev/null
}

repo_count() {
	awk 'NF > 0 && $1 !~ /^#/ { count++ } END { print count + 0 }' "$REPOS" 2>/dev/null
}

current_target() {
	if [ -L "$CURRENT" ]; then
		readlink "$CURRENT" 2>/dev/null || true
	else
		echo "not-a-symlink"
	fi
}

contract() {
	cat <<EOF
MixtarRVS generation/package boundary contract:
  profile: $PROFILE
  current generation link: $CURRENT
  generation root: $GENERATIONS
  toolkit root: $TOOLS
  package backend: apk
  apk world: $WORLD
  apk repositories: $REPOS

Implemented:
  check
  status
  profile
  world
  repos
  packages
  backend
  closure
  build --dry-run

Policy:
  MixtarRVS owns the visible generation model.
  apk remains a hidden compatibility backend until MixtarRVS can build, switch, boot, rollback, and garbage-collect generations itself.

Not implemented yet:
  build generation activation
  switch generation
  boot generation
  rollback
  garbage collection
  image/rootfs builder
  visual package manager
EOF
}

print_check_line() {
	label=$1
	shift
	"$@" 2>/dev/null | awk -v label="$label" 'NR == 1 { print label "=" $0; found = 1 } END { if (!found) print label "=missing" }'
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

build_dry_run() {
	echo "plan=mixtar-generation-build"
	echo "mode=dry-run"
	echo "would_create_generation=false"
	echo "would_activate_generation=false"
	echo "would_run_apk_add=false"
	echo "would_run_apk_del=false"
	echo "would_run_apk_upgrade=false"
	echo "would_rewrite_apk_world=false"
	echo "would_rewrite_apk_repositories=false"
	echo "current_link=$CURRENT"
	echo "current_target=$(current_target)"
	echo "generation_root=$GENERATIONS"
	echo "next_generation=not-allocated-dry-run"
	echo "root_model=$(field root_model)"
	echo "activation_model=dry-run-only"
	echo "toolkit_root=$TOOLS"
	echo "toolkit_count=$(toolkit_count)"
	echo "package_backend=apk"
	echo "package_count=$(package_count)"
	echo "world_file=$WORLD"
	echo "world_count=$(world_count)"
	echo "repositories_file=$REPOS"
	echo "repository_count=$(repo_count)"
	echo "kernel_profile=$(readlink /System/Kernel/Current 2>/dev/null || echo missing)"
	echo "kernel_vmlinuz=/System/Kernel/Current/vmlinuz"
	echo "kernel_initramfs=/System/Kernel/Current/initramfs.img"
	echo "runtime_libraries=/System/Libraries/MixtarRVS/Runtime/0003/lib"
	echo "service_manifests=/System/Config/Services"
	echo "network_profile=/System/Config/Network/current.network"
	echo "remote_profile=/System/Config/RemoteAccess/current.remote"
	echo "generation_profile=$PROFILE"
	echo "base_closure_stage_count=$(ls -1 /System/Base/Closure 2>/dev/null | count_lines)"
	print_check_line "generation_check" /System/SystemTools/mixtar-generation check
	print_check_line "service_check" /System/SystemTools/mixtar-service check
	print_check_line "network_check" /System/SystemTools/mixtar-network check
	print_check_line "remote_check" /System/SystemTools/mixtar-remote check
	tool_state apk
	tool_state tar
	tool_state gzip
	tool_state xz
	tool_state zstd
	tool_state sha256sum
	tool_state mksquashfs
	tool_state unsquashfs
	if command -v mksquashfs >/dev/null 2>&1; then
		echo "image_builder_ready=true"
	else
		echo "image_builder_ready=false"
		echo "missing_image_builder=mksquashfs"
	fi
	if [ -d /System/Libraries/MixtarRVS/Runtime/0003/lib ]; then
		echo "runtime_libraries_ready=true"
	else
		echo "runtime_libraries_ready=false"
	fi
	if [ -f /System/Base/Closure/0005-initramfs-contract-and-fallback-init-shim/manifest.json ]; then
		echo "initramfs_contract_ready=true"
	else
		echo "initramfs_contract_ready=false"
	fi
	echo "dry_run_result=plan-generated"
	echo "buildable_now=false"
	if command -v mksquashfs >/dev/null 2>&1; then
		echo "build_blocker=activation/switch/rollback not implemented"
	else
		echo "build_blocker=image builder missing and activation/switch/rollback not implemented"
	fi
}

show_profile() {
	cat "$PROFILE"
}

show_world() {
	cat "$WORLD"
}

show_repos() {
	cat "$REPOS"
}

show_packages() {
	"$APK" info
}

show_backend() {
	awk -F= '
		$1 == "identity" { print "identity=" $2 }
		$1 == "package_backend" { print "package_backend=" $2 }
		$1 == "package_backend_visibility" { print "package_backend_visibility=" $2 }
		$1 == "package_world" { print "package_world=" $2 }
		$1 == "package_repositories" { print "package_repositories=" $2 }
		$1 == "root_model" { print "root_model=" $2 }
		$1 == "activation_model" { print "activation_model=" $2 }
	' "$PROFILE"
	if [ -x "$APK" ]; then
		echo "apk=$APK"
		"$APK" --version | awk '{ print "apk_version=" $0 }'
	else
		echo "apk=missing"
	fi
	if command -v mksquashfs >/dev/null 2>&1; then
		echo "mksquashfs=present"
	else
		echo "mksquashfs=missing"
	fi
}

show_closure() {
	echo "current_link=$CURRENT"
	echo "current_target=$(current_target)"
	echo "generation_root=$GENERATIONS"
	echo "toolkit_root=$TOOLS"
	echo "toolkit_count=$(toolkit_count)"
	echo "package_count=$(package_count)"
	echo "world_count=$(world_count)"
	echo "repository_count=$(repo_count)"
	echo "stage_count=$(ls -1 /System/Base/Closure 2>/dev/null | count_lines)"
	echo "root_model=$(field root_model)"
	echo "fallback_policy=$(field fallback_policy)"
}

status() {
	echo "profile=$PROFILE"
	show_closure
	show_backend
}

check() {
	rc=0
	if [ ! -f "$PROFILE" ]; then
		echo "missing profile: $PROFILE" >&2
		return 1
	fi
	for path in "$CURRENT" "$GENERATIONS" "$TOOLS" "$WORLD" "$REPOS"; do
		if [ ! -e "$path" ]; then
			echo "missing path: $path" >&2
			rc=1
		fi
	done
	if [ ! -x "$APK" ]; then
		echo "missing apk backend: $APK" >&2
		rc=1
	fi
	tools=$(toolkit_count)
	if [ "$tools" -lt 158 ]; then
		echo "toolkit count too low: $tools" >&2
		rc=1
	fi
	packages=$(package_count)
	if [ "$packages" -lt 1 ]; then
		echo "apk package inventory empty" >&2
		rc=1
	fi
	world=$(world_count)
	if [ "$world" -lt 1 ]; then
		echo "apk world empty" >&2
		rc=1
	fi
	repos=$(repo_count)
	if [ "$repos" -lt 1 ]; then
		echo "apk repositories empty" >&2
		rc=1
	fi
	if [ "$rc" -eq 0 ]; then
		echo "ok generation=current toolkit=$tools packages=$packages backend=apk-hidden"
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
	status)
		status
		;;
	profile)
		show_profile
		;;
	world)
		show_world
		;;
	repos)
		show_repos
		;;
	packages)
		show_packages
		;;
	backend)
		show_backend
		;;
	closure)
		show_closure
		;;
	build)
		mode=${2:-}
		if [ "$mode" != "--dry-run" ]; then
			usage
			exit 2
		fi
		build_dry_run
		;;
	*)
		usage
		exit 2
		;;
esac
