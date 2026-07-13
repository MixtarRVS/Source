# msh-category: builtin
# msh-name: break ignores extra operands in loop
while true; do
    break 1 2
    printf '%s\n' bad
done
printf '%s\n' after
