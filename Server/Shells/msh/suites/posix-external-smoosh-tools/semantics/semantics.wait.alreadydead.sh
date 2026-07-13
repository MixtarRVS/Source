# msh-source: smoosh/tests/shell/semantics.wait.alreadydead.test
# msh-profile: posix
# msh-run: eval
sleep 10 &
pid=$!
sleep 1
kill $pid
echo kill ec: $?
sleep 1
wait $pid
echo wait ec: $?
