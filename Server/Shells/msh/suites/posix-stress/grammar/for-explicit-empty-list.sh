# msh-category: grammar
# msh-name: for explicit empty list
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
for x in; do
    printf bad
done
printf ok
