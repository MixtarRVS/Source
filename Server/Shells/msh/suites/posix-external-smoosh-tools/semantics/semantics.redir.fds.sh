# msh-source: smoosh/tests/shell/semantics.redir.fds.test
# msh-profile: posix
# msh-run: eval
$TEST_UTIL/fds
exec 3>&1
$TEST_UTIL/fds
