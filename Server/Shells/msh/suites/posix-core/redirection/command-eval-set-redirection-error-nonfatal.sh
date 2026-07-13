# msh-category: redirection
# msh-name: command eval set redirection error is nonfatal
# msh-profile: posix
command eval 'set -f < definitely_missing_file'
printf 'after\n'
