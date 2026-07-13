# msh-category: builtin
# msh-name: trap signal resets listed term trap
# msh-profile: posix
trap 'printf hit' TERM
trap TERM
trap
printf done