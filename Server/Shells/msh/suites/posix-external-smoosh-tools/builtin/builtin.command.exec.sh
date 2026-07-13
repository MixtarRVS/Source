# msh-source: smoosh/tests/shell/builtin.command.exec.test
# msh-profile: posix
# msh-run: eval
echo hi >file
command exec 8<file
read msg <&8
echo $msg