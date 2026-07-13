# msh-source: smoosh/tests/shell/semantics.wait.alreadydead.test
# msh-profile: posix
# msh-run: eval
$TEST_SHELL -c 'while :; do :; done' &
pid=$!
kill "$pid"
echo kill ec: $?
wait "$pid"
echo wait ec: $?
