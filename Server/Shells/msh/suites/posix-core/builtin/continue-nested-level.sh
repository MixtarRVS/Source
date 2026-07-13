# msh-profile: posix
i=0
j=0
while [ "$i" -lt 2 ]; do
  i=$((i + 1))
  while :; do
    j=$((j + 1))
    continue 2
    j=99
  done
  i=99
done
printf '%s:%s\n' "$i" "$j"