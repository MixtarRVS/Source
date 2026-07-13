# msh-source: smoosh/tests/shell/semantics.errexit.carryover.test
# msh-profile: posix
# msh-run: eval
set -e
putsn() { echo "$@"; }
false && true
putsn "It should be executed"
false && true
/bin/echo hello
