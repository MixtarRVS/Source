# msh-source: smoosh/tests/shell/semantics.redir.indirect.test
# msh-profile: posix
# msh-run: eval
f() {
    echo message >&2
}

msg=$(f 2>&1)
[ "$msg" = "message" ] || exit 1

unset msg
x=1
msg=$(f 2>&$x)
[ "$msg" = "message" ] || exit 2

echo ok