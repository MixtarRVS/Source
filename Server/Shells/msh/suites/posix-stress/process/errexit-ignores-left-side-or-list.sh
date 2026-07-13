# msh-category: process
# msh-name: errexit ignores left side or list
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -e
false || printf ok
