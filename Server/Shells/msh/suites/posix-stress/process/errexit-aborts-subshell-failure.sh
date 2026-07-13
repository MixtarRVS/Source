# msh-category: process
# msh-name: errexit aborts subshell failure
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
(false)
printf after
