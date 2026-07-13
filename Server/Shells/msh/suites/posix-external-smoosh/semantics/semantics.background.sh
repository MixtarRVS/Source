# msh-source: smoosh/tests/shell/semantics.background.test
# msh-profile: posix
# msh-run: eval
echo hi
$TEST_SHELL -c 'echo derp' >bg.out &
echo bye
wait
read bg <bg.out
echo "$bg"
