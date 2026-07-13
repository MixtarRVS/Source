# msh-category: builtin
# msh-name: read temporary IFS assignment
printf 'a:b:c\n' > in
IFS=: read A B < in
printf '%s|%s|%s\n' "$A" "$B" "$?"
printf 'x:y z\n' > in2
read C D < in2
printf '%s|%s\n' "$C" "$D"
