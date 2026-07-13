# msh-category: builtin
# msh-name: command assignment break temporary
while true; do
    A=inner command break
done
printf '<%s>\n' "${A-unset}"
