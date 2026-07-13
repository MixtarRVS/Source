# msh-source: smoosh/tests/shell/semantics.background.pipe.pid.test
# msh-profile: posix
# msh-run: eval
echo 'echo $$ > pid.out' >showpid.sh
chmod +x showpid.sh
true | $TEST_SHELL showpid.sh &
sleep 1
[ "$!" -eq "$(cat pid.out)" ]