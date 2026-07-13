# msh-source: smoosh/tests/shell/builtin.dot.path.test
# msh-profile: posix
# msh-run: eval
set -e
printf 'echo path-dot-ok\n' >scr2
PATH=/definitely/not/here:.
. scr2
