# msh-category: builtin
# msh-name: export readonly assignment aborts
readonly A=1
export A=2
printf '%s\n' after
