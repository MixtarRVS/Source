# msh-source: smoosh/tests/shell/semantics.background.pipe.pid.test
# msh-profile: posix
# msh-run: eval
printf x | $TEST_SHELL -c 'IFS= read -r x; printf "%s\n" "$$" >pid.out' &
bgpid=$!
wait "$bgpid"
IFS= read -r childpid <pid.out
[ "$bgpid" -eq "$childpid" ] && echo ok
