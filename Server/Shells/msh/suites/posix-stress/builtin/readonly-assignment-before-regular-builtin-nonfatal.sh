# msh-category: builtin
# msh-name: readonly assignment before regular builtin nonfatal
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
readonly A
A=x echo hi
printf after
