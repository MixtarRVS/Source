# msh-category: builtin
# msh-name: dot double dash sources following operand
printf 'VALUE=ok\n' > file
. -- ./file
printf '%s\n' "$VALUE"
