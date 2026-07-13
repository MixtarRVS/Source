# msh-category: redirection
# msh-name: bad fd number output redirection-only aborts
# msh-stderr: normalized
>&bad
printf 'after\n'
