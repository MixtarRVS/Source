# msh-source: smoosh/tests/shell/builtin.trap.chained.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01771.html
trap exit INT
trap 'true; kill -s INT $$' EXIT
false
