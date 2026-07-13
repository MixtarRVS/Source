# msh-category: builtin
# msh-name: command eval unset readonly nonfatal
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
readonly A=1
command eval 'unset A'
printf after
