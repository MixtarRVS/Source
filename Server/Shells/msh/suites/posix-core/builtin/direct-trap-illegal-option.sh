# msh-category: builtin
# msh-name: direct trap illegal option
trap -l
printf 'after:%s\n' $?
