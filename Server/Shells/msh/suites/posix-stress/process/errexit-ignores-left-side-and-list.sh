# msh-category: process
# msh-name: errexit ignores left side and list
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
false && printf bad
printf ok
