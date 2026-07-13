# msh-category: process
# msh-name: trap action exit controls status
trap 'exit 7' TERM
kill -TERM $$
printf after
