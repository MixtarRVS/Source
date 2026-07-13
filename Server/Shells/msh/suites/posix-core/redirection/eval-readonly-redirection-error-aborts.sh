# msh-category: redirection
# msh-name: eval readonly redirection error aborts
# msh-profile: posix
eval 'readonly A=1 < definitely_missing_file'
printf 'after\n'
