# msh-category: redirection
# msh-name: set redirection error aborts
# msh-profile: posix
set -f < definitely_missing_file
printf 'after\n'
