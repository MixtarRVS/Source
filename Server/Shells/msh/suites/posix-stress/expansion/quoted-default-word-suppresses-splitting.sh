# msh-category: expansion
# msh-name: quoted default word suppresses splitting
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
unset A
B='x y'
for x in "${A:-$B}"; do
    printf '<%s>' "$x"
done
printf '\n'
