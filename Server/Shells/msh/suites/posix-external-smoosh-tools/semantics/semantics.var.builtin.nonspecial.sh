# msh-source: smoosh/tests/shell/semantics.var.builtin.nonspecial.test
# msh-profile: posix
# msh-run: eval
# successful command
unset x
x=value command alias >/dev/null 2>&1
echo ${x-unset}
test -z "$x" || exit 1

# unsuccessful command
unset x
x=value command alias -: >/dev/null 2>&1
echo ${x-unset}
test -z "$x" || exit 2
