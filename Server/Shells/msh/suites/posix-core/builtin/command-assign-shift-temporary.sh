# msh-category: builtin
# msh-name: command assignment shift temporary
set -- a b
A=outer
A=inner command shift
printf '<%s:%s>\n' "$A" "$1"
