# msh-category: redirection
# msh-name: shift redirection error aborts
# msh-profile: posix
set -- a
shift < definitely_missing_file
printf 'after\n'
