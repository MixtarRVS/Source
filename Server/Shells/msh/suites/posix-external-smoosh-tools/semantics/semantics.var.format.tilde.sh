# msh-source: smoosh/tests/shell/semantics.var.format.tilde.test
# msh-profile: posix
# msh-run: eval
unset x
tilde=~
: ${x:=~}
ext=~/foo
[ "$x" = "$tilde" ] && \
[ "/foo" = ${ext#~} ] && \
! $TEST_SHELL -c 'echo ${y?~}'