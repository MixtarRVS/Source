# msh-source: smoosh/tests/shell/builtin.times.ioerror.test
# msh-profile: posix
# msh-run: eval
exec 3>&1
(
        trap "" PIPE
        sleep 1
        command times
        echo ?=$? >&3
) | true
