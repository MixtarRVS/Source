# msh-category: redirection
# msh-name: bad fd number output special aborts
# msh-stderr: normalized
: >&bad
printf 'after\n'
