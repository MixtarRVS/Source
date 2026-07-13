# msh-category: builtin
# msh-name: assignment before export persists
# msh-profile: posix
A=outer
A=inner export B=two
printf '<%s/%s>\n' "$A" "$B"
