# msh-category: redirection
# msh-name: command readonly redirection error is nonfatal
# msh-profile: posix
command readonly A=1 < definitely_missing_file
printf 'after\n'
