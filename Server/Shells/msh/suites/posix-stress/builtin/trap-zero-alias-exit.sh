# msh-category: builtin
# msh-name: trap zero alias exit
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
trap 'printf bye' 0
exit 0
