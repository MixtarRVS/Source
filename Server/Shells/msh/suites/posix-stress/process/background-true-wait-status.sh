# msh-category: process
# msh-name: background true wait status
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
true &
pid=$!
wait "$pid"
printf '<%s>\n' "$?"
