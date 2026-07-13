# msh-category: builtin
# msh-name: command eval unset readonly is nonfatal
readonly A=1
command eval 'unset A'
printf 'after\n'
