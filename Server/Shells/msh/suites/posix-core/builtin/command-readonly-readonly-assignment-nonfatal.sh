# msh-category: builtin
# msh-name: command readonly readonly assignment is nonfatal
readonly A=1
command readonly A=2
printf '%s\n' after
