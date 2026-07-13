# msh-category: builtin
# msh-name: verbose eval quoted newline read unit
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -v
eval 'printf ok
printf done'; printf after
