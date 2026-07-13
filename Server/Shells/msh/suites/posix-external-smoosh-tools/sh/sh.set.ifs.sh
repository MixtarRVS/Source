# msh-source: smoosh/tests/shell/sh.set.ifs.test
# msh-profile: posix
# msh-run: eval
cat >show_ifs <<EOF
printf '%s' "$IFS"
EOF
$TEST_SHELL show_ifs || exit 1
export IFS=123
$TEST_SHELL show_ifs || exit 1
IFS=abc $TEST_SHELL show_ifs || exit 1
