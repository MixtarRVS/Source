# msh-category: builtin
# msh-name: unset v variable
A=old
unset -v A
printf '<%s>' "$A"