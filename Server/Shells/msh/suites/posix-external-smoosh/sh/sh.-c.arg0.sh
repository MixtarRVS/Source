# msh-source: smoosh/tests/shell/sh.-c.arg0.test
# msh-profile: posix
# msh-run: eval
printf '%s\n' 'echo "i am $0, hear me roar"' >scr
$TEST_SHELL -c '. "$0"' ./scr
