# msh-source: smoosh/tests/shell/builtin.dot.break.test
# msh-profile: posix
# msh-run: eval
echo break >scr
for x in a b c
do
  echo $x
  . ./scr
done