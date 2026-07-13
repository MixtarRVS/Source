# msh-category: builtin
# msh-name: command set error is nonfatal
# msh-profile: posix
command set -o definitely-not-posix
status=$?
A=ok
printf '%s %s\n' "$status" "$A"
