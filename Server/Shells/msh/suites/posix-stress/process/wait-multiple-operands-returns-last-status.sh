# msh-category: process
# msh-name: wait multiple operands returns last status
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
false & p1=$!
true & p2=$!
wait "$p1" "$p2"
printf '<%s>\n' "$?"
