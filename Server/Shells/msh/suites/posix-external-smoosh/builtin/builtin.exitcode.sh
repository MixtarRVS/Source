# msh-source: smoosh/tests/shell/builtin.exitcode.test
# msh-profile: posix
# msh-run: eval
high_exit() {
    return 42
}

COMMANDS=": true false pwd echo times eval set trap command umask alias unalias wait read test [ printf kill getopts"

echo Leaking commands:
for command in $COMMANDS; do
    high_exit
    $command </dev/null >/dev/null 2>/dev/null
    rc=$?
    if [ "$rc" -eq 42 ]; then
        echo "$command"
    fi
done
