# msh-category: builtin
# msh-name: set positional after options
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -f -- a b
printf '<%s><%s><%s>\n' "$1" "$2" "$-"
