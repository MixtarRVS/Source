# msh-name: assignment before eval persists and is visible to eval body
# msh-profile: posix
A=one eval 'B=$A'
printf '<%s/%s>\n' "$A" "$B"
