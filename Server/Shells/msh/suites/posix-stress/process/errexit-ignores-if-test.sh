# msh-category: process
# msh-name: errexit ignores if test
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
if false; then
    printf bad
fi
printf ok
