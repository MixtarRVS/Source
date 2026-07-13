# msh-category: builtin
# msh-name: command assignment set temporary
A=outer
A=inner command set -- x
printf '<%s:%s>\n' "$A" "$1"
