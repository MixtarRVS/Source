# msh-source: smoosh/tests/shell/semantics.slash.glob.test
# msh-profile: posix
# msh-run: eval
arg_len() {
    echo $#
}

trap 'rm -r foo' EXIT

mkdir foo
touch foo/a foo/b foo/c
[ "$(arg_len foo//*)" -eq 3 ] && echo OK
