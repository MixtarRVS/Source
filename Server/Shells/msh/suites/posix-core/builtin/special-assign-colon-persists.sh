# msh-category: builtin
# msh-name: assignment before colon persists
# msh-profile: posix
A=outer
A=inner :
printf '<%s>\n' "$A"
