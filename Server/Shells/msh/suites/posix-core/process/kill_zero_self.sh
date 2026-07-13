# msh-category: process
# msh-name: kill zero self
kill -0 $$
printf $?
