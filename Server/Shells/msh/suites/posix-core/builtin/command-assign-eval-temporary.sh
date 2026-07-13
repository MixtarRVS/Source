# msh-name: assignment before command eval is temporary but visible to eval
# msh-profile: posix
A=old
A=one command eval 'B=$A'
printf '<%s/%s>\n' "$A" "$B"
