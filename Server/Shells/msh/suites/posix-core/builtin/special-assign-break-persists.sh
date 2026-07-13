# msh-name: assignment before break persists after loop control
# msh-profile: posix
while true; do
    A=one break
    A=bad
done
printf '<%s>\n' "$A"
