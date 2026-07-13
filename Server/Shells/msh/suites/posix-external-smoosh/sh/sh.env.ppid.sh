# msh-source: smoosh/tests/shell/sh.env.ppid.test
# msh-profile: posix
# msh-run: eval
inner=$($TEST_SHELL -c 'printf "%s" "$PPID"')
[ "$inner" -eq "$$" ] && echo ok
