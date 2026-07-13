# msh-source: smoosh/tests/shell/semantics.redir.nonregular.test
# msh-profile: posix
# msh-run: eval
set -C
: >/dev/null || exit 2
echo ok
