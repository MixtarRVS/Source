# msh-category: redirection
# msh-name: noclobber command eval colon is nonfatal
printf old > f
set -C
command eval ': > f'
printf 'after status:%s\n' "$?"
