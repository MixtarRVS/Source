# msh-category: redirection
# msh-name: trap redirection error aborts
# msh-profile: posix
trap < definitely_missing_file
printf 'after\n'
