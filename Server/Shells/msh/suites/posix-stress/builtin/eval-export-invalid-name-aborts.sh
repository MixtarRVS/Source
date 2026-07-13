# msh-category: builtin
# msh-name: eval export invalid name aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
eval 'export 1BAD=value'
printf after
