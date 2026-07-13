# msh-name: command readonly redirection stderr
# msh-stderr: normalized
command readonly A=1 < definitely_missing_file
printf after
