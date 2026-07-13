# msh-source: smoosh/tests/shell/builtin.source.setvar.test
# msh-profile: posix
# msh-run: eval
set -e
printf '%s\n' 'x=5' >to_source
source ./to_source
echo ${x?:unset}
[ "$x" -eq 5 ]
