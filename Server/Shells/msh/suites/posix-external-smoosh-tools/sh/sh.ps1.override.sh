# msh-source: smoosh/tests/shell/sh.ps1.override.test
# msh-profile: posix
# msh-run: eval
unset PS1
$TEST_SHELL -i <<EOF
echo hi
echo bye
EOF

PS1='PS1$ ' $TEST_SHELL -i <<EOF
echo hi
echo bye
EOF