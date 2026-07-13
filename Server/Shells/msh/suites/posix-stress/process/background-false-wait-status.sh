# msh-category: process
# msh-name: background false wait status
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
false &
pid=$!
wait "$pid"
printf '<%s>\n' "$?"
