# msh-category: builtin
# msh-name: readonly rejects later assignment
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
readonly A=1
A=2
printf after
