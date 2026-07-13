# msh-category: builtin
# msh-name: test grouped negation
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
[ ! \( '' -o foo \) ]
printf '<%s>\n' "$?"
