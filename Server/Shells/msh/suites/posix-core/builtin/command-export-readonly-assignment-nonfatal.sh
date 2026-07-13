# msh-category: builtin
# msh-name: command export readonly assignment is nonfatal
readonly A=1
command export A=2
printf '%s\n' after
