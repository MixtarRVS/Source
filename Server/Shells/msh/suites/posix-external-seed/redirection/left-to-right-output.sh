printf old > out
{ printf new; } > out 2>&1
read X < out
printf '<%s>\n' "$X"
