# msh-category: process
# msh-name: kill trapped term self
trap 'printf term' TERM
kill -TERM $$
printf done
