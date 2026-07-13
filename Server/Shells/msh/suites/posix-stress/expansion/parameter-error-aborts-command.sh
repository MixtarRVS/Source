# msh-category: expansion
# msh-name: parameter error aborts command
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
unset A
printf '%s\n' "${A:?boom}"
printf after
