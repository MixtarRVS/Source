#!/bin/sh
set -eu

tools_dir="/System/Tools/MixtarRVS/bin"
manifest="/System/Config/MixtarRVS/userland-source-only.manifest"
source_list="/System/Config/MixtarRVS/userland-source-tools.txt"

line() {
  printf '%s\n' "$*"
}

status_path() {
  path="$1"
  if [ -L "$path" ]; then
    line "compat-link $path -> $(readlink "$path")"
  elif [ -d "$path" ]; then
    line "dir         $path"
  elif [ -e "$path" ]; then
    line "file        $path"
  else
    line "missing     $path"
  fi
}

line "MixtarRVS base-closure report"
line "kernel: $(uname -r)"
line "machine: $(uname -m)"
line ""

if [ -d "$tools_dir" ]; then
  tool_count=$(find "$tools_dir" -type f -perm -111 | wc -l | tr -d ' ')
  line "tools_dir: ok $tools_dir"
  line "tools_count: $tool_count"
else
  line "tools_dir: missing $tools_dir"
fi

if [ -r "$manifest" ]; then
  metadata_lines=$(wc -l < "$manifest" | tr -d ' ')
  line "manifest: ok $manifest"
  line "metadata_manifest_lines: $metadata_lines"
else
  line "manifest: missing $manifest"
fi

if [ -r "$source_list" ]; then
  source_count=$(wc -l < "$source_list" | tr -d ' ')
  line "source_list: ok $source_list"
  line "source_count: $source_count"
else
  line "source_list: missing $source_list"
fi

line ""
line "PATH resolution with MixtarRVS first:"
PATH="/System/Tools/MixtarRVS/bin:/System/SystemTools:/bin:/sbin:/usr/bin:/usr/sbin"
export PATH
for cmd in uname ls cat cp mv rm grep sed awk ps find sort wc head tail chmod ln mkdir rmdir; do
  resolved=$(command -v "$cmd" 2>/dev/null || true)
  line "$cmd -> ${resolved:-missing}"
done

line ""
line "Mixtar identity paths:"
for path in /Applications /Compatibility /Programs /System /Temporary /Users /Volumes; do
  status_path "$path"
done

line ""
line "POSIX/bootstrap compatibility paths:"
for path in /bin /sbin /lib /usr/bin /usr/sbin /usr/lib /etc /run /dev /proc /sys; do
  status_path "$path"
done

line ""
line "OpenRC/bootstrap services:"
if command -v rc-status >/dev/null 2>&1; then
  rc-status 2>/dev/null || true
else
  line "rc-status: missing"
fi
