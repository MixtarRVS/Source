# msh-category: command-search
# msh-name: alias suppressed by command
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
alias true=false
command true
printf '<%s>\n' "$?"
