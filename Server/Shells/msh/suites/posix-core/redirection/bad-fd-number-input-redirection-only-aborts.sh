# msh-category: redirection
# msh-name: bad fd number input redirection-only aborts
# msh-stderr: normalized
<&bad
printf 'after\n'
