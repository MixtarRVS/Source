# msh-category: redirection
# msh-name: command eval unset redirection error is nonfatal
# msh-profile: posix
A=1
command eval 'unset A < definitely_missing_file'
printf 'after\n'
