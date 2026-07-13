# msh-category: builtin
# msh-name: command readonly violation nonfatal
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
A=1
readonly A
command readonly A=2
printf after
