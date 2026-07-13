# msh-category: expansion
# msh-name: unquoted dollar star with nonwhite ifs
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -- 'a:b' c
IFS=:
for x in $*; do
    printf '<%s>' "$x"
done
printf '\n'
