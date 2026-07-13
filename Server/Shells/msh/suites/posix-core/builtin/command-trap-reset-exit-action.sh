# msh-category: builtin
# msh-name: command trap signal resets existing exit trap
# msh-profile: posix
trap 'printf hit' EXIT
command trap EXIT
printf done