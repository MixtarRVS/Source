# msh-category: redirection
# msh-name: noclobber command colon is nonfatal
# msh-stderr: normalized
printf old > f
set -C
command : > f
printf 'after status:%s\n' "$?"
