# msh-source: smoosh/tests/shell/builtin.trap.subshell.false.exit.test
# msh-profile: posix
# msh-run: eval
trap "(false) && echo BUG" EXIT
