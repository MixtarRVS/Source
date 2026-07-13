# msh-category: builtin
# msh-name: test repeated negation unary
# msh-profile: extension
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
[ ! ! -n foo ]
printf '<%s>\n' "$?"
