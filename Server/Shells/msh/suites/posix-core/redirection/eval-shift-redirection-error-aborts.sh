# msh-category: redirection
# msh-name: eval shift redirection error aborts
# msh-profile: posix
set -- a
eval 'shift < definitely_missing_file'
printf 'after\n'
