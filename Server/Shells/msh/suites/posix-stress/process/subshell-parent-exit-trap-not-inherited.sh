# msh-category: process
# msh-name: subshell parent exit trap not inherited
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
trap 'echo bye' EXIT
(echo hi)
echo $(echo hi)
