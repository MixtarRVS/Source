# msh-source: smoosh/tests/shell/semantics.background.test
# msh-profile: posix
# msh-run: eval
echo hi
{ sleep 1 ; echo derp ; } &
echo bye
wait