# msh-source: smoosh/tests/shell/builtin.trap.supershell.test
# msh-profile: posix
# msh-run: eval
trap 'echo bye' EXIT
(trap)
(trap 'echo so long' EXIT; trap)
(trap)
