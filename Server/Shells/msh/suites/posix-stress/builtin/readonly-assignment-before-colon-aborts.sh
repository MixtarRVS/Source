# msh-category: builtin
# msh-name: readonly assignment before colon aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
readonly A
A=x :
printf after
