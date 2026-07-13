# msh-source: smoosh/tests/shell/semantics.errexit.trap.test
# msh-profile: posix
# msh-run: eval
set -e; trap "false; echo BUG" USR1; kill -s USR1 $$
