# msh-category: redirection
# msh-name: command eval trap redirection error is nonfatal
# msh-profile: posix
command eval 'trap < definitely_missing_file'
printf 'after\n'
