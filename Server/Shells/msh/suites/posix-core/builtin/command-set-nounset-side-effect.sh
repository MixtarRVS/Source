# msh-category: builtin
# msh-name: command set nounset keeps option side effect
# msh-profile: posix
# msh-status: exact
set +u
command set -u
printf 'before\n'
printf '%s\n' "$MISSING"
printf 'after\n'
