# msh-category: builtin
# msh-name: command shift negative count is nonfatal
set -- a
command shift -1
printf '%s\n' after
