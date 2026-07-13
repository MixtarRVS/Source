# msh-source: smoosh/tests/shell/builtin.command.nospecial.test
# msh-profile: posix
# msh-run: eval
command readonly x=foo
command readonly x=bar
echo ?=$?
