# msh-category: redirection
# msh-name: noclobber exec aborts
# msh-stderr: normalized
printf old > f
set -C
exec > f
printf 'after status:%s\n' "$?"
