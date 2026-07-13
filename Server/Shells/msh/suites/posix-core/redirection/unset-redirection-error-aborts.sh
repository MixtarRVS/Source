# msh-category: redirection
# msh-name: unset redirection error aborts
# msh-profile: posix
A=1
unset A < definitely_missing_file
printf 'after\n'
