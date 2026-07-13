# msh-category: builtin
# msh-name: command set o noclobber keeps option side effect
# msh-profile: posix
printf old > command-set-o-noclobber.out
set +C
command set -o noclobber
printf new > command-set-o-noclobber.out
printf 'after\n'
