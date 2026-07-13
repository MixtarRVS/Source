# msh-source: smoosh/tests/shell/builtin.trap.exit.subshell.test
# msh-profile: posix
# msh-run: eval
trap 'echo bye' EXIT
(echo hi)
echo $(echo hi)
