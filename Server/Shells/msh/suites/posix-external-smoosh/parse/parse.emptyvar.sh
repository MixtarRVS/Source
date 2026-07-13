# msh-source: smoosh/tests/shell/parse.emptyvar.test
# msh-profile: posix
# msh-run: eval
err=$($TEST_SHELL -c ': ${}' 2>&1 >/dev/null)
[ "$err" ]


