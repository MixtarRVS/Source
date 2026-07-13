# msh-category: builtin
# msh-name: set option before plain operands
# msh-profile: posix
set -f a b
printf '%s,%s,%s:%s\n' "$1" "$2" "$#" "$-"
