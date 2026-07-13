# msh-source: smoosh/tests/shell/semantics.arith.assign.multi.test
# msh-profile: posix
# msh-run: eval
: $((x = y = z = 0))
echo $x $y $z