# msh-source: smoosh/tests/shell/builtin.source.setvar.test
# msh-profile: posix
# msh-run: eval
set -e

echo 'x=5' >to_source
source ./to_source
echo ${x?:unset}
rm to_source
[ "$x" -eq 5 ]