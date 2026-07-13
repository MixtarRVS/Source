# msh-category: redirection
# msh-name: bad fd number output command special aborts
# msh-stderr: normalized
command : >&bad
printf 'after\n'
