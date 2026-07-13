# msh-source: smoosh/tests/shell/builtin.pwd.exitcode.test
# msh-profile: posix
# msh-run: eval
# Make sure that pwd sets its exitcode.
false
pwd >/dev/null 2>/dev/null && echo OK
