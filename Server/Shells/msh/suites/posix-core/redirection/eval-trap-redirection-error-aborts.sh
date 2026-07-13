# msh-category: redirection
# msh-name: eval trap redirection error aborts
# msh-profile: posix
eval 'trap < definitely_missing_file'
printf 'after\n'
