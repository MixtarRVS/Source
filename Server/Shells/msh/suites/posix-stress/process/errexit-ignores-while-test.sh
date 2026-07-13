# msh-category: process
# msh-name: errexit ignores while test
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
while false; do
    printf bad
done
printf ok
