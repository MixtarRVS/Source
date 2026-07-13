# msh-source: smoosh/tests/shell/semantics.backtick.ppid.test
# msh-profile: posix
# msh-run: eval
set -e
$TEST_SHELL -c 'echo $PPID' >pid1
$TEST_SHELL -c 'echo $PPID' >pid2
read a <pid1
read b <pid2
[ "$a" = "$b" ] || exit 2
printf '%s\n' pid1=pid2
(echo $PPID) >ppid
read c <ppid
[ "$PPID" = "$c" ] || exit 3
printf '%s\n' ppid=subshell
