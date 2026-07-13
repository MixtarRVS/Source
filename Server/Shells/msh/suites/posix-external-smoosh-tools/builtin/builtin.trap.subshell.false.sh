# msh-source: smoosh/tests/shell/builtin.trap.subshell.false.test
# msh-profile: posix
# msh-run: eval
trap "(false) && echo BUG" INT; kill -s INT $$
