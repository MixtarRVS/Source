# msh-category: builtin
# msh-name: command eval trap illegal option
command eval 'trap -l'
printf 'after:%s\n' $?
