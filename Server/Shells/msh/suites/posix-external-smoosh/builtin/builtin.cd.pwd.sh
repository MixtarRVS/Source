# msh-source: smoosh/tests/shell/builtin.cd.pwd.test
# msh-profile: posix
# msh-run: eval
pwd -P >/dev/null
orig=$(pwd)
[ "$orig" = "$PWD" ] || exit 1
cd .
[ "$orig" = "$PWD" ] || exit 2
[ "$(pwd)" = "$PWD" ] || exit 3
echo ok
