# msh-category: process
# msh-name: subshell trap does not alter parent
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
trap 'printf parent' EXIT
(trap 'printf sub' EXIT)
printf main
