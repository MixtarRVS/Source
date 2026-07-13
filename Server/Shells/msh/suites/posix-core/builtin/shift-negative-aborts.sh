# msh-category: builtin
# msh-name: shift negative count aborts
set -- a
shift -1
printf '%s\n' after
