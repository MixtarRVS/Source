# msh-source: smoosh/tests/shell/builtin.command.keyword.test
# msh-profile: posix
# msh-run: eval
# ADDTOPOSIX
set -e
command -v !
command -v while
command -V while >/dev/null 2>&1
type do >/dev/null 2>&1