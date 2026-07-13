# msh-category: builtin
# msh-name: test repeated negation empty
# msh-profile: extension
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
[ ! ! '' ]
printf '<%s>\n' "$?"
