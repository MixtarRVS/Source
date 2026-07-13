# msh-category: builtin
# msh-name: command readonly error is nonfatal
# msh-profile: posix
command readonly 1BAD
status=$?
A=ok
printf '%s %s\n' "$status" "$A"
