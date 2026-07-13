# msh-category: builtin
# msh-name: eval set plain operands become positionals
# msh-profile: posix
eval 'set a b'
printf '%s,%s,%s\n' "$1" "$2" "$#"
