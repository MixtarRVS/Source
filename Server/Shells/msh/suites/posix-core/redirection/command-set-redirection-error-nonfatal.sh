# msh-category: redirection
# msh-name: command set redirection error is nonfatal
# msh-profile: posix
command set -f < definitely_missing_file
printf 'after\n'
