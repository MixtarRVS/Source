# msh-category: process
# msh-name: errexit ignores negated pipeline
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
! false
printf ok
