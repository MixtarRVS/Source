# msh-source: smoosh/tests/shell/semantics.traps.async.test
# msh-profile: posix
# msh-run: eval
( 
kill -s QUIT $($TEST_SHELL -c 'echo $PPID') || exit 1 
echo done
) &
wait $!
