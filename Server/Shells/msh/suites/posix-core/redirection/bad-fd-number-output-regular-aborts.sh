# msh-category: redirection
# msh-name: bad fd number output regular aborts
# msh-stderr: normalized
true >&bad
printf 'after\n'
