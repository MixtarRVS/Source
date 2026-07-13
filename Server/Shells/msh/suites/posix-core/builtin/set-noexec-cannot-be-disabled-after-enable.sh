# msh-category: builtin
# msh-name: set noexec prevents later plus noexec from running
# msh-profile: posix
set -n
set +n
printf 'after\n'
