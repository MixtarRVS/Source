# msh-category: expansion
# msh-name: ifs mixed whitespace and colon
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
IFS=' :'
set -- ' a:: b :'
for x in $1; do
    printf '<%s>' "$x"
done
printf '\n'
