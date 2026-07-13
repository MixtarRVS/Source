# msh-category: builtin
# msh-name: command unset v variable
A=old
command unset -v A
printf '<%s>' "$A"