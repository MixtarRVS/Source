# msh-category: expansion
# msh-name: quoted star and at separation
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -- 'a b' c
printf '<%s>' "$*"
for x in "$@"; do
    printf '[%s]' "$x"
done
printf '\n'
