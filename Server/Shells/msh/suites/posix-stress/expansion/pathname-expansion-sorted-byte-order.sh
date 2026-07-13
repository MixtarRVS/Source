# msh-category: expansion
# msh-name: pathname expansion sorted byte order
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
> pb
> pa
for x in p?; do
    printf '<%s>' "$x"
done
printf '\n'
