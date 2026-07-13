# msh-source: smoosh/tests/shell/sh.set.ifs.test
# msh-profile: posix
# msh-run: eval
printf '%s\n' 'printf %s "$IFS"' >show_ifs
$TEST_SHELL show_ifs || exit 1
export IFS=123
$TEST_SHELL show_ifs || exit 1
IFS=abc $TEST_SHELL show_ifs || exit 1
