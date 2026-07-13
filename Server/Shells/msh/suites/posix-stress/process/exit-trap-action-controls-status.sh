# msh-category: process
# msh-name: exit trap action controls status
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
trap 'exit 7' EXIT
false
