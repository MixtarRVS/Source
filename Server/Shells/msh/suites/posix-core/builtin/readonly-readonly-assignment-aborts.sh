# msh-category: builtin
# msh-name: readonly readonly assignment aborts
readonly A=1
readonly A=2
printf '%s\n' after
