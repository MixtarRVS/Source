# msh-category: builtin
# msh-name: command set plus noclobber keeps option side effect
# msh-profile: posix
printf old > command-set-plus-noclobber.out
set -C
command set +C
printf new > command-set-plus-noclobber.out
read X < command-set-plus-noclobber.out
printf '%s:%s\n' "$X" "$?"
