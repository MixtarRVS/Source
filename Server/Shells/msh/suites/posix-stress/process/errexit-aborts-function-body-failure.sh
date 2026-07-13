# msh-category: process
# msh-name: errexit aborts function body failure
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
f() { false; printf after; }
f
printf end
