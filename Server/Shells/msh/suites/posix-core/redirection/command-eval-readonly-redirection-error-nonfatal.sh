# msh-category: redirection
# msh-name: command eval readonly redirection error is nonfatal
# msh-profile: posix
command eval 'readonly A=1 < definitely_missing_file'
printf 'after\n'
