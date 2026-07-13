# msh-category: expansion
# msh-name: unquoted command substitution drops empty fields
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
X=$(printf 'a\n\nb\n')
for x in $X; do
    printf '<%s>' "$x"
done
printf '\n'
