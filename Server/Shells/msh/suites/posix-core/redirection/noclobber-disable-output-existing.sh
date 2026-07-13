# msh-category: redirection
# msh-name: set plus C disables noclobber
printf old > noclobber-disable.out
set -C
set +C
printf new > noclobber-disable.out
printf 's=%s ' "$?"
read X < noclobber-disable.out
printf 'x=%s flags=%s\n' "$X" "$-"
