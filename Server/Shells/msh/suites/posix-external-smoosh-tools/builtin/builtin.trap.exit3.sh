# msh-source: smoosh/tests/shell/builtin.trap.exit3.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01750.html
trap '(exit 3) && echo BUG' INT
kill -s INT $$
