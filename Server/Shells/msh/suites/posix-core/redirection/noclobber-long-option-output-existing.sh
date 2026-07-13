# msh-category: redirection
# msh-name: set -o noclobber blocks output redirection
# msh-stderr: normalized
printf old > noclobber-long.out
set -o noclobber
printf new > noclobber-long.out
printf 's=%s ' "$?"
read X < noclobber-long.out
printf 'x=%s flags=%s\n' "$X" "$-"
