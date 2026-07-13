# msh-category: process
# msh-name: trap double dash self signal
trap -- 'printf int' INT
kill -INT $$
printf done