# msh-category: redirection
# msh-name: command eval shift redirection error is nonfatal
# msh-profile: posix
set -- a
command eval 'shift < definitely_missing_file'
printf 'after\n'
