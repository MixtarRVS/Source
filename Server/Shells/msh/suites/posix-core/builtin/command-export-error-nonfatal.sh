# msh-category: builtin
# msh-name: command export error is nonfatal
# msh-profile: posix
command export 1BAD
status=$?
A=ok
printf '%s %s\n' "$status" "$A"
