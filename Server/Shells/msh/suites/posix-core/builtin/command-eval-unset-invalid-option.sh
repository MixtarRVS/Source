# msh-category: builtin
# msh-name: command eval unset invalid option
command eval 'unset -z'
printf 'after:%s\n' $?
