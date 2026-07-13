# msh-category: redirection
# msh-name: special builtin bad output fd aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
: >&9
printf after
