# msh-name: assignment before continue persists after loop control
# msh-profile: posix
i=0
while [ "$i" -lt 1 ]; do
    i=$((i + 1))
    A=one continue
    A=bad
done
printf '<%s/%s>\n' "$A" "$i"
