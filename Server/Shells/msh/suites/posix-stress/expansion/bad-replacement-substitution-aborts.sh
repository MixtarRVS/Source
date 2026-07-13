# msh-category: expansion
# msh-name: bad replacement substitution aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
A=abc
printf '<%s>\n' "${A/b/x}"
printf after
