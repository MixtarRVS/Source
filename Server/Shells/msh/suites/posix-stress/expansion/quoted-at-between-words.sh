# msh-category: expansion
# msh-name: quoted at between words
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -- 'a b' c
for x in pre"$@"post; do
    printf '<%s>' "$x"
done
printf '\n'
