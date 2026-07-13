# msh-category: expansion
# msh-name: arithmetic command substitution expands variable name
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
B=4
printf '<%s>\n' "$(( $(printf B) + 1 ))"
