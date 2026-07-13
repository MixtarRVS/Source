# msh-category: builtin
# msh-name: command assignment colon temporary
A=outer
A=inner command :
printf '<%s>\n' "$A"
