# msh-category: redirection
# msh-name: command eval times redirection error is nonfatal
# msh-profile: posix
command eval 'times < definitely_missing_file'
printf 'after\n'
