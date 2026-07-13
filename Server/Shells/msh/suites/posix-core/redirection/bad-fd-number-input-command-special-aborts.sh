# msh-category: redirection
# msh-name: bad fd number input command special aborts
# msh-stderr: normalized
command : <&bad
printf 'after\n'
