# msh-category: process
# msh-name: trap action preserves interrupted command status
trap 'false' TERM
kill -TERM $$
printf 's:%s\n' "$?"
