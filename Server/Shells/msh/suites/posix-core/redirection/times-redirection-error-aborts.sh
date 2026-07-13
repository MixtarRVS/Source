# msh-category: redirection
# msh-name: times redirection error aborts
# msh-profile: posix
times < definitely_missing_file
printf 'after\n'
