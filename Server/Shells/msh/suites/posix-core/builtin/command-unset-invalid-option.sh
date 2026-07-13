# msh-category: builtin
# msh-name: command unset invalid option
command unset -z
printf 'after:%s\n' $?
