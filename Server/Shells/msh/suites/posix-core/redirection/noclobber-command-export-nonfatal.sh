# msh-category: redirection
# msh-name: noclobber command export is nonfatal
# msh-stderr: normalized
printf old > f
set -C
command export A=1 > f
printf 'after status:%s A=%s\n' "$?" "$A"
