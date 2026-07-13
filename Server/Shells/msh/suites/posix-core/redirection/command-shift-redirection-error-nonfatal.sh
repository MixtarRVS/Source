# msh-category: redirection
# msh-name: command shift redirection error is nonfatal
# msh-profile: posix
set -- a
command shift < definitely_missing_file
printf 'after\n'
