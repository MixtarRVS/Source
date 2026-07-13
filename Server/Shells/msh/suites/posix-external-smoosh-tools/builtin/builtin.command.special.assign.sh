# msh-source: smoosh/tests/shell/builtin.command.special.assign.test
# msh-profile: posix
# msh-run: eval
unset x
x=whoops command :
echo ${x-unset}