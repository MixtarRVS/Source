# msh-category: builtin
# msh-name: command assignment exec no command temporary
A=outer
A=inner command exec
printf '<%s>\n' "$A"
