# msh-category: builtin
# msh-name: command set noclobber keeps option side effect
# msh-profile: posix
printf old > command-set-noclobber.out
set +C
command set -C
printf new > command-set-noclobber.out
printf 'after\n'
