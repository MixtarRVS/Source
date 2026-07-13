# msh-source: smoosh/tests/shell/semantics.tilde.sep.test
# msh-profile: posix
# msh-run: eval
# ADDTOPOSIX
[ ~: = "~:" ] || exit 1

y=~
[ $y = "$HOME" ] || exit 2

y=~/foo
[ $y = "$HOME/foo" ] || exit 3

y=~:foo
[ $y = "$HOME:foo" ] || exit 4

y=foo:~
[ $y = "foo:$HOME" ] || exit 5

y=foo:~:bar
[ $y = "foo:$HOME:bar" ] || exit 6

echo ok