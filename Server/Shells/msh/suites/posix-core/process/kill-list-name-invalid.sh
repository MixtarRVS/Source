# msh-category: process
# msh-name: kill list name invalid
kill -l TERM
printf 's=%s\n' "$?"
