# msh-category: redirection
# msh-name: noclobber eval colon aborts
printf old > f
set -C
eval ': > f'
printf 'after status:%s\n' "$?"
