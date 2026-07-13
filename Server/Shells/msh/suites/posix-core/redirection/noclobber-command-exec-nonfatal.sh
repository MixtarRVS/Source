# msh-category: redirection
# msh-name: noclobber command exec is nonfatal
# msh-stderr: normalized
printf old > f
set -C
command exec > f
printf 'after status:%s\n' "$?"
