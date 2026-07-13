# msh-category: redirection
# msh-name: noclobber export aborts
# msh-stderr: normalized
printf old > f
set -C
export A=1 > f
printf 'after status:%s A=%s\n' "$?" "$A"
