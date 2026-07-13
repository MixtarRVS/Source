# msh-source: smoosh/tests/shell/builtin.export.unset.test
# msh-profile: posix
# msh-run: eval
set -e
unset x
export x
export -p | grep 'export x'
echo ok