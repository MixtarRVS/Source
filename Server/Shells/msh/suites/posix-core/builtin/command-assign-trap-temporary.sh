# msh-category: builtin
# msh-name: command assignment trap temporary
A=outer
A=inner command trap >/dev/null
printf '<%s>\n' "$A"
