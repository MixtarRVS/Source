# msh-source: smoosh/tests/shell/semantics.tilde.test
# msh-profile: posix
# msh-run: eval
echo ~ >tilde.out
var=~
echo $var > var.out
[ -s tilde.out ] && [ -s var.out ] || exit 1
read t <tilde.out
read v <var.out
[ "$t" = "$v" ] && [ "$t" != "~" ]
