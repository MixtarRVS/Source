# msh-profile: posix
i=0
while :; do
  while :; do
    i=1
    break 2
    i=2
  done
  i=3
done
printf '%s\n' "$i"