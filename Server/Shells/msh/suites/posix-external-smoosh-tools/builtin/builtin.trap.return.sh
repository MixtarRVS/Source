# msh-source: smoosh/tests/shell/builtin.trap.return.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01792.html
trap 'f() { false; return; }; f; echo $?' EXIT