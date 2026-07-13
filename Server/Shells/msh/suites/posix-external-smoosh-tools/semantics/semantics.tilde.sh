# msh-source: smoosh/tests/shell/semantics.tilde.test
# msh-profile: posix
# msh-run: eval
echo ~ >tilde.out
var=~
echo $var > var.out
[ -f tilde.out ] && [ -f var.out ] && \
[ -s tilde.out ] && [ -s var.out ] && \
[ $(cat tilde.out) = $(cat var.out) ] && \
[ $(cat tilde.out) != "~" ]

