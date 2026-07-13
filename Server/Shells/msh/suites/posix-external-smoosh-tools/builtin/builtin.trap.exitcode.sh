# msh-source: smoosh/tests/shell/builtin.trap.exitcode.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01770.html

trap 'set -o bad@option' INT
kill -s INT $$
