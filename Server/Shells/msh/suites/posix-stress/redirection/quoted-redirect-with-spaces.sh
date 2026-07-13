# msh-category: redirection
# msh-name: quoted redirect with spaces
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A='x y'
: > "$A"
if [ -f 'x y' ]; then
    printf ok
else
    printf bad
fi
