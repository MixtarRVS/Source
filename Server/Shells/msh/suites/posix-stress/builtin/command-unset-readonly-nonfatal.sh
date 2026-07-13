# msh-category: builtin
# msh-name: command unset readonly nonfatal
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
readonly A=1
command unset A
printf after
