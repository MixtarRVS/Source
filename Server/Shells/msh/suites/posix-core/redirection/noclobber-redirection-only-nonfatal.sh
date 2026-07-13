# msh-category: redirection
# msh-name: noclobber redirection-only is nonfatal
# msh-stderr: normalized
printf old > f
set -C
> f
printf 'after status:%s\n' "$?"
