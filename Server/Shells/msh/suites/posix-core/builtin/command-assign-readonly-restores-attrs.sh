# msh-category: builtin
# msh-name: command assignment readonly restores attributes
A=outer
A=inner command readonly A
printf '<%s>\n' "$A"
A=next
printf 's=%s A=<%s>\n' "$?" "$A"
