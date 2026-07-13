# msh-category: builtin
# msh-name: shift updates positional count
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -- a b c
shift 2
printf '<%s:%s>\n' "$1" "$#"
