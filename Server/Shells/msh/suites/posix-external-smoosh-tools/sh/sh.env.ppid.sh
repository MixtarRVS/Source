# msh-source: smoosh/tests/shell/sh.env.ppid.test
# msh-profile: posix
# msh-run: eval
$TEST_SHELL -c 'echo $PPID' >ppid
inner=$(cat ppid)
rm ppid
[ "$inner" -eq "$$" ]

