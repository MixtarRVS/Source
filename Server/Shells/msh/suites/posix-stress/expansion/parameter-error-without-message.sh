# msh-category: expansion
# msh-name: parameter error without message
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
unset A
printf '%s\n' "${A?}"
printf after
