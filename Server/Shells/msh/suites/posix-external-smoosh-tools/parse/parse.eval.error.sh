# msh-source: smoosh/tests/shell/parse.eval.error.test
# msh-profile: posix
# msh-run: eval
cat >scr <<EOF
eval "if"
echo lived
EOF
$TEST_SHELL scr && exit 1
exit 0