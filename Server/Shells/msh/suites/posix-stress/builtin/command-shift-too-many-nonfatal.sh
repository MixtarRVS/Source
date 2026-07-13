# msh-category: builtin
# msh-name: command shift too many nonfatal
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
set -- a b
command shift 3
printf after
