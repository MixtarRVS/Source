# msh-category: builtin
# msh-name: command assignment unset restores original
A=outer
A=inner command unset A
printf '<%s>\n' "${A:-missing}"
