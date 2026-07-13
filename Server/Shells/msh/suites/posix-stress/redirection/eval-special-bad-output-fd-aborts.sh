# msh-category: redirection
# msh-name: eval special bad output fd aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
eval ': >&9'
printf after
