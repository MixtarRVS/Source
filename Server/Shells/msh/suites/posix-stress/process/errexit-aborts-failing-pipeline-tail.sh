# msh-category: process
# msh-name: errexit aborts failing pipeline tail
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
true | false
printf after
