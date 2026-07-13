# msh-source: smoosh/tests/shell/semantics.background.pid.test
# msh-profile: posix
# msh-run: eval
$TEST_SHELL -c 'printf "%s\n" "$$" >pid.out' &
bgpid=$!
wait "$bgpid"
IFS= read -r childpid <pid.out
[ "$bgpid" -eq "$childpid" ] && echo ok
