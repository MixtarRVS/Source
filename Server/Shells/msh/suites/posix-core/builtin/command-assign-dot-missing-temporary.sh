# msh-category: builtin
# msh-name: command assignment missing dot temporary
A=outer
A=inner command . ./missing-file
status=$?
printf '<%s:%s>\n' "$A" "$status"
