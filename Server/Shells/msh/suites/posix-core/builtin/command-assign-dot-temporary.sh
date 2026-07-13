# msh-name: assignment before command dot is temporary but visible to source
# msh-profile: posix
printf 'B=$A\n' > command-dot-source.tmp
A=old
A=one command . ./command-dot-source.tmp
printf '<%s/%s>\n' "$A" "$B"
