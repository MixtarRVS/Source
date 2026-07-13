# msh-category: expansion
# msh-name: command substitution unquoted newline splitting
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
X=$(printf 'a\nb\n')
for x in $X; do
    printf '<%s>' "$x"
done
printf '\n'
