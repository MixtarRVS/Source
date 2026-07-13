# msh-category: builtin
# msh-name: command dot double dash sources following operand
printf 'VALUE=ok\n' > file
command . -- ./file
printf '%s\n' "$VALUE"
