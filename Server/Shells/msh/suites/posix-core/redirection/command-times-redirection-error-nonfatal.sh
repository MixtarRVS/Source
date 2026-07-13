# msh-category: redirection
# msh-name: command times redirection error is nonfatal
# msh-profile: posix
command times < definitely_missing_file
printf 'after\n'
