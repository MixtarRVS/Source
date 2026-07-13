# msh-category: expansion
# msh-name: arithmetic nonnumeric variable aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
A=B
B=4
printf '<%s>\n' "$((A+1))"
printf after
