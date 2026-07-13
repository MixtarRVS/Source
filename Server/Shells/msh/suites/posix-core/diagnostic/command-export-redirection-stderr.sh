# msh-name: command export redirection stderr
# msh-stderr: normalized
command export A=1 < definitely_missing_file
printf after
