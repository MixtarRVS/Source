# msh-category: builtin
# msh-name: eval unset invalid option
eval 'unset -z'
printf 'after:%s\n' $?
