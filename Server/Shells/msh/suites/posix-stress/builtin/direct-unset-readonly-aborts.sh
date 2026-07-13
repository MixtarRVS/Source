# msh-category: builtin
# msh-name: direct unset readonly aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
readonly A=1
unset A
printf after
