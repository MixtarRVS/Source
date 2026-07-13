# msh-source: smoosh/tests/shell/builtin.eval.test
# msh-profile: posix
# msh-run: eval
echo starting
eval echo hi
echo nice
eval "x=bye"
echo $x

