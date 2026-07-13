# msh-category: builtin
# msh-name: eval unset readonly aborts
readonly A
eval 'unset A'
printf 'after\n'
