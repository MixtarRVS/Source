# msh-name: special redirection abort stderr
# msh-stderr: normalized
export A=1 < definitely_missing_file
printf after
