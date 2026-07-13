# msh-category: redirection
# msh-name: bad fd exec aborts
# msh-stderr: normalized
exec 3>&9
printf 'after\n'
