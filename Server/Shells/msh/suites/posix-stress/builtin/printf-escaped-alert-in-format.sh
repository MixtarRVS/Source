# msh-category: builtin
# msh-name: printf escaped alert in format
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
X=$(printf '\a')
printf '<%s>\n' "${#X}"
