# msh-category: redirection
# msh-name: noclobber blocks output redirection to existing file
# msh-stderr: normalized
printf old > noclobber-block.out
set -C
printf new > noclobber-block.out
printf 's=%s ' "$?"
read X < noclobber-block.out
printf 'x=%s flags=%s\n' "$X" "$-"
