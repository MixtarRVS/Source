# msh-category: process
# msh-name: subshell exit status
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
(exit 5)
printf '<%s>\n' "$?"
