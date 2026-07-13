# msh-category: builtin
# msh-name: direct unset invalid option
unset -z
printf 'after:%s\n' $?
