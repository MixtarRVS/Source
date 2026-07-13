# msh-category: builtin
# msh-name: command set plain operands become positionals
# msh-profile: posix
set old
command set a b
printf '%s,%s,%s\n' "$1" "$2" "$#"
