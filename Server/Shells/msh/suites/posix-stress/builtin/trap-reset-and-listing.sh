# msh-category: builtin
# msh-name: trap reset and listing
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
trap 'printf bad' TERM
trap - TERM
trap
printf done
