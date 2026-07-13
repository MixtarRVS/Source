# msh-category: builtin
# msh-name: command assignment continue temporary
i=0
while [ "$i" -lt 1 ]; do
    i=1
    A=inner command continue
done
printf '<%s>\n' "${A-unset}"
