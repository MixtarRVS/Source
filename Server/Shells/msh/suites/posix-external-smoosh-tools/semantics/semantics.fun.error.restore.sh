# msh-source: smoosh/tests/shell/semantics.fun.error.restore.test
# msh-profile: posix
# msh-run: eval
set -u

f() {
    echo $1
    echo <none
}

set -- a b c
f arg1 arg2
printf '<%s>\n' "$@"
