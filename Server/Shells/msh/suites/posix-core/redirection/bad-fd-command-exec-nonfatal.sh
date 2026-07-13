# msh-category: redirection
# msh-name: bad fd command exec is nonfatal
# msh-stderr: normalized
command exec 3>&9
printf 'after status:%s\n' "$?"
