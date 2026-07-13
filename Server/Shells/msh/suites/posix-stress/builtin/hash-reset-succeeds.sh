# msh-category: builtin
# msh-name: hash reset succeeds
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
hash -r
printf '<%s>\n' "$?"
