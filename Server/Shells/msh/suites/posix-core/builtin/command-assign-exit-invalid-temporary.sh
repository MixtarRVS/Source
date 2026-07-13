# msh-category: builtin
# msh-name: command assignment invalid exit temporary
A=outer
A=inner command exit x
status=$?
printf '<%s:%s>\n' "$A" "$status"
