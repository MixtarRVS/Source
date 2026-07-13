# msh-category: builtin
# msh-name: set plus o noclobber disables clobber guard
# msh-profile: posix
printf old > set-plus-o-noclobber.out
set -o noclobber
set +o noclobber
printf new > set-plus-o-noclobber.out
read X < set-plus-o-noclobber.out
printf '%s:%s\n' "$X" "$?"
