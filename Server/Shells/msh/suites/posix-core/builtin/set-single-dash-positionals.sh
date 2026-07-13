# msh-category: builtin
# msh-name: set single dash before operands
# msh-profile: posix
set - a b
printf '%s,%s,%s\n' "$1" "$2" "$#"
