# msh-category: redirection
# msh-name: closed output fd special aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
exec 8>out
exec 8>&-
: >&8
printf after
