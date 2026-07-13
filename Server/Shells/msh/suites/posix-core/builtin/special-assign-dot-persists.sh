# msh-category: builtin
# msh-name: assignment before dot persists
# msh-profile: posix
printf 'B=$A\n' > source.sh
A=inner . ./source.sh
printf '<%s/%s>\n' "$A" "$B"
