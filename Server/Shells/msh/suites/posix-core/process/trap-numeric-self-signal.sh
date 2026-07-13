# msh-category: process
# msh-name: numeric signal trap dispatch
trap 'printf int' 2
kill -INT $$
printf done
