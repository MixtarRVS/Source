# msh-name: dot missing path stderr
# msh-stderr: normalized
PATH=.
. definitely_missing_file
printf after
