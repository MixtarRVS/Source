# msh-category: builtin
# msh-name: command set plus o noclobber keeps option side effect
# msh-profile: posix
printf old > command-set-plus-o-noclobber.out
set -o noclobber
command set +o noclobber
printf new > command-set-plus-o-noclobber.out
read X < command-set-plus-o-noclobber.out
printf '%s:%s\n' "$X" "$?"
