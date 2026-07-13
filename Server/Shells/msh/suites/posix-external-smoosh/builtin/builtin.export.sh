# msh-source: smoosh/tests/shell/builtin.export.test
# msh-profile: posix
# msh-run: eval
printf '%s\n' 'echo ${var-unset}' >scr
$TEST_SHELL scr
var=hi
$TEST_SHELL scr
var=here $TEST_SHELL scr
export var=bye
$TEST_SHELL scr
