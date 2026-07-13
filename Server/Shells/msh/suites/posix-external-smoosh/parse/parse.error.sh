# msh-source: smoosh/tests/shell/parse.error.test
# msh-profile: posix
# msh-run: eval
printf '%s\n' ')' >scr
$TEST_SHELL scr || echo sh ok
$TEST_SHELL -c '. ./scr' || echo dot ok
