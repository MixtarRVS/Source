# msh-category: builtin
# msh-name: set noexec skips subsequent commands
# msh-profile: posix
printf 'before\n'
set -n
printf 'after\n'
