# msh-category: builtin
# msh-name: eval trap illegal option
eval 'trap -l'
printf 'after:%s\n' $?
