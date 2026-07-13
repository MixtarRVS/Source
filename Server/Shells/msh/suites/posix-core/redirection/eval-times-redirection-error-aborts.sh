# msh-category: redirection
# msh-name: eval times redirection error aborts
# msh-profile: posix
eval 'times < definitely_missing_file'
printf 'after\n'
