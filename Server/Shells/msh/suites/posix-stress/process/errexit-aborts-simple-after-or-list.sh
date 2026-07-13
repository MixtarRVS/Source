# msh-category: process
# msh-name: errexit aborts simple after or list
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
true || printf bad
false
printf after
