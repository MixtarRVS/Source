# msh-category: process
# msh-name: background pipeline pid wait
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf X | read X &
pid=$!
wait "$pid"
printf '<%s>\n' "$?"
