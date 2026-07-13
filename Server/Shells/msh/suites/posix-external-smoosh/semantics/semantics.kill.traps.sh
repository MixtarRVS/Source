# msh-source: smoosh/tests/shell/semantics.kill.traps.test
# msh-profile: posix
# msh-run: eval
$TEST_SHELL -c 'while :; do :; done' &
pid=$!
kill "$pid"
[ "$?" -eq 0 ] || exit 1
wait "$pid"
[ "$?" -ge 128 ] || exit 2
