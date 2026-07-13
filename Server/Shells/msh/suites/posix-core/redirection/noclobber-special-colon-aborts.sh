# msh-category: redirection
# msh-name: noclobber special colon aborts
# msh-stderr: normalized
printf old > f
set -C
: > f
printf 'after status:%s\n' "$?"
