# msh-category: redirection
# msh-name: eval set redirection error aborts
# msh-profile: posix
eval 'set -f < definitely_missing_file'
printf 'after\n'
