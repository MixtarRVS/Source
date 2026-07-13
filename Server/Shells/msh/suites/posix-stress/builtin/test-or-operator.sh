# msh-category: builtin
# msh-name: test or operator
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
[ '' -o bar ]
printf '<%s>\n' "$?"
