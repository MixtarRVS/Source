# msh-source: smoosh/tests/shell/semantics.arith.var.space.test
# msh-profile: posix
# msh-run: eval
x="  8"
y=$((x + 1))
echo $x $y
