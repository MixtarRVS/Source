# msh-category: process
# msh-name: subshell trap list resets parent action
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
trap 'echo bye' EXIT
(trap)
(trap 'echo so long' EXIT; trap)
(trap)
