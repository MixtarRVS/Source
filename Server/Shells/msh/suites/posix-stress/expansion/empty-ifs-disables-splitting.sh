# msh-category: expansion
# msh-name: empty ifs disables splitting
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
IFS=
A='a b c'
for x in $A; do
    printf '<%s>' "$x"
done
printf '\n'
