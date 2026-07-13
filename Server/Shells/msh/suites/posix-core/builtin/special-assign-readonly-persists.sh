# msh-category: builtin
# msh-name: assignment before readonly persists
# msh-profile: posix
A=outer
A=inner readonly B=two
printf '<%s/%s>\n' "$A" "$B"
