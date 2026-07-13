# msh-category: process
# msh-name: errexit ignores function used as if test
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
f() { false; printf ok; }
if f; then
    printf done
fi
