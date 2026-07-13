# msh-category: builtin
# msh-name: eval unset readonly aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
readonly A=1
eval 'unset A'
printf after
