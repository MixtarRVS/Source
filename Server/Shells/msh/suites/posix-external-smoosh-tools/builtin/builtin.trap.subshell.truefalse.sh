# msh-source: smoosh/tests/shell/builtin.trap.subshell.truefalse.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01750.html
trap '(false) && echo BUG' INT; kill -s INT $$
trap "(false) && echo BUG" EXIT
trap "(false); echo \$?" EXIT
