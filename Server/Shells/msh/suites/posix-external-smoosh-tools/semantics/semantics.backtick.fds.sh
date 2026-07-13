# msh-source: smoosh/tests/shell/semantics.backtick.fds.test
# msh-profile: posix
# msh-run: eval
set -e
subshfds=$($TEST_UTIL/fds 0 20)
$TEST_UTIL/fds 0 20
echo $subshfds
