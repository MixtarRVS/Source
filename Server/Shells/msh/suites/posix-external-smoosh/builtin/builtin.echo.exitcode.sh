# msh-source: smoosh/tests/shell/builtin.echo.exitcode.test
# msh-profile: posix
# msh-run: eval
# Make sure that echo properly sets its exitcode.
echo >/dev/null && echo OK
echo >/dev/full || echo OK
