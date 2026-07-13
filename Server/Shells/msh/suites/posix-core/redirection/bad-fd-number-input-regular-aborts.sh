# msh-category: redirection
# msh-name: bad fd number input regular aborts
# msh-stderr: normalized
true <&bad
printf 'after\n'
