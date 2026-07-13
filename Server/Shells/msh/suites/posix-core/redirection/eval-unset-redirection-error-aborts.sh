# msh-category: redirection
# msh-name: eval unset redirection error aborts
# msh-profile: posix
A=1
eval 'unset A < definitely_missing_file'
printf 'after\n'
