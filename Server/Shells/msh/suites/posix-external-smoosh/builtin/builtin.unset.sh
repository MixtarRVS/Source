# msh-source: smoosh/tests/shell/builtin.unset.test
# msh-profile: posix
# msh-run: eval
readonly x=foo
y=bar
unset y
echo ${y-unset}
echo ${x-error}
unset y
echo ${y-unset}
unset x
