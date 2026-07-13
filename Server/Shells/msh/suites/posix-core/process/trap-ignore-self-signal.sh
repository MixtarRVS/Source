# msh-category: process
# msh-name: ignored self signal continues
trap '' TERM
kill -TERM $$
printf 'after:%s\n' "$?"
