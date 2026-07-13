# msh-category: expansion
# msh-name: backquote command substitution quoted
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf '<%s>\n' "`printf 'a b'`"
