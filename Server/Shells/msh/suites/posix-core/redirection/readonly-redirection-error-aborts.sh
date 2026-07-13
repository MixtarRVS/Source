# msh-category: redirection
# msh-name: readonly redirection error aborts
# msh-profile: posix
readonly A=1 < definitely_missing_file
printf 'after\n'
