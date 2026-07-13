# msh-category: builtin
# msh-name: set plain operands become positionals
# msh-profile: posix
set a b
printf '%s,%s,%s\n' "$1" "$2" "$#"
