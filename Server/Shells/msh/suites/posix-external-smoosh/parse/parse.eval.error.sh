# msh-source: smoosh/tests/shell/parse.eval.error.test
# msh-profile: posix
# msh-run: eval
printf '%s\n' 'eval "if"' 'echo lived' >scr
$TEST_SHELL scr && exit 1
exit 0
