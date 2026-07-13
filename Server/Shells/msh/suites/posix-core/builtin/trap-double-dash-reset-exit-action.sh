# msh-category: builtin
# msh-name: trap double dash signal resets existing exit trap
# msh-profile: posix
trap 'printf hit' EXIT
trap -- EXIT
printf done