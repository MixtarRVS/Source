# msh-category: process
# msh-name: errexit ignores function used as while test
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
f() { false; printf ok; }
while f; do
    printf bad
    break
done
printf done
