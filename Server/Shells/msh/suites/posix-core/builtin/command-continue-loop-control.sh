i=0
while [ "$i" -lt 2 ]; do
    i=$((i + 1))
    command continue
    printf bad
done
printf '%s' "$i"
