# msh-category: process
# msh-name: last background pid updates after failure
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
false & p1=$!
true & p2=$!
[ "$p1" = "$p2" ] && printf same || printf different
wait "$p1" 2>/dev/null
wait "$p2" 2>/dev/null
