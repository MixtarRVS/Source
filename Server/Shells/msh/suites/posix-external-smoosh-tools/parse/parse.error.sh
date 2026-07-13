# msh-source: smoosh/tests/shell/parse.error.test
# msh-profile: posix
# msh-run: eval
echo ')' >scr
$TEST_SHELL scr || echo sh ok
{ echo eval ')' | $TEST_SHELL -i ; } || echo eval ok
$TEST_SHELL -c '. ./scr' || echo dot ok
