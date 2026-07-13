# msh-category: builtin
# msh-name: command shift error is nonfatal
# msh-profile: posix
command shift x
status=$?
A=ok
printf '%s %s\n' "$status" "$A"
