# msh-source: smoosh/tests/shell/semantics.arith.pos.test
# msh-profile: posix
# msh-run: eval
a=+47
[ $((a)) -eq 47 ]
echo $((a))