# msh-category: builtin
# msh-name: continue ignores extra operands in loop
i=0
while [ "$i" -lt 2 ]; do
    i=$((i + 1))
    continue 1 2
    printf '%s\n' bad
done
printf '<%s>\n' "$i"
