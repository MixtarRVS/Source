# msh-category: redirection
# msh-name: force clobber overrides noclobber
printf old > noclobber-force.out
set -C
printf new >| noclobber-force.out
printf 's=%s ' "$?"
read X < noclobber-force.out
printf 'x=%s flags=%s\n' "$X" "$-"
