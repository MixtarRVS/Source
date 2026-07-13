# msh-category: builtin
# msh-name: test and operator
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
[ foo -a bar ]
printf '<%s>\n' "$?"
