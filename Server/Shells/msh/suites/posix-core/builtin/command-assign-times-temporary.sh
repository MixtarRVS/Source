# msh-category: builtin
# msh-name: command assignment times temporary
A=outer
A=inner command times >/dev/null
printf '<%s>\n' "$A"
