# msh-category: process
# msh-name: background group pid wait
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
{ printf X > out; } &
pid=$!
wait "$pid"
read X < out
printf '<%s>\n' "$?"
printf '<%s>\n' "$X"
