# msh-category: redirection
# msh-name: bad output fd command special is nonfatal
# msh-stderr: normalized
command : 3>&9
printf 'after status:%s\n' "$?"
