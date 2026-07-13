# msh-category: builtin
# msh-name: printf escaped alert in percent b
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
X=$(printf '%b' '\a')
printf '<%s>\n' "${#X}"
