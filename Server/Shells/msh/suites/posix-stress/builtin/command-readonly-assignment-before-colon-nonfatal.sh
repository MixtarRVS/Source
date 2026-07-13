# msh-category: builtin
# msh-name: command readonly assignment before colon nonfatal
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
readonly A
A=x command :
printf after
