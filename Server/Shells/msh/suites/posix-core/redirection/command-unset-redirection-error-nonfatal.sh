# msh-category: redirection
# msh-name: command unset redirection error is nonfatal
# msh-profile: posix
A=1
command unset A < definitely_missing_file
printf 'after\n'
