# msh-source: smoosh/tests/shell/builtin.trap.nested.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01762.html
trap '(trap "echo exit" EXIT; :)' EXIT