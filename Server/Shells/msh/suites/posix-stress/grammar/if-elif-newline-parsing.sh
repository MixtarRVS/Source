# msh-category: grammar
# msh-name: if elif newline parsing
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
if false
then
    printf bad
elif true
then
    printf ok
else
    printf bad
fi
