# msh-category: builtin
# msh-name: command eval set plain operands become positionals
# msh-profile: posix
set old
command eval 'set a b'
printf '%s,%s,%s\n' "$1" "$2" "$#"
