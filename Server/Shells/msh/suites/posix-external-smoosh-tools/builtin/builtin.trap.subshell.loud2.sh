# msh-source: smoosh/tests/shell/builtin.trap.subshell.loud2.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01766.html
trap 'set -o bad@option' INT; kill -s INT $$ && echo HUH
trap '(:; exit) && echo WEIRD' EXIT; false