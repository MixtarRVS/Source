# msh-category: redirection
# msh-name: command trap redirection error is nonfatal
# msh-profile: posix
command trap < definitely_missing_file
printf 'after\n'
