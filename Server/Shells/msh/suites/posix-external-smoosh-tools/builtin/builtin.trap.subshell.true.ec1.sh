# msh-source: smoosh/tests/shell/builtin.trap.subshell.true.ec1.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01761.html
trap '(true) || echo bug' EXIT; false
