# msh-source: smoosh/tests/shell/builtin.trap.subshell.loud.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01766.html
trap '(:; exit) && echo WEIRD' EXIT; false