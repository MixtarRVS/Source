# msh-category: expansion
# msh-name: arithmetic invalid octal variable aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
A=08
printf '<%s>\n' "$((A+1))"
printf after
