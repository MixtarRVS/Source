# msh-category: redirection
# msh-name: bad output fd special builtin aborts
# msh-stderr: normalized
: 3>&9
printf 'after\n'
