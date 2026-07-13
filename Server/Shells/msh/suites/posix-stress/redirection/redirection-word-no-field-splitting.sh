# msh-category: redirection
# msh-name: redirection word no field splitting
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A='a b'
: > $A
if [ -f 'a b' ]; then
    printf ok
else
    printf bad
fi
