# msh-category: builtin
# msh-name: unset double dash variable
A=old
unset -- A
printf '<%s>' "$A"