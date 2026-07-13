set -C
printf old > out
: > out 2>/dev/null
printf 'status=%s\n' "$?"
printf new >| out
read X < out
printf '<%s>\n' "$X"
