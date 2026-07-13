# msh-source: smoosh/tests/shell/semantics.var.dashu.test
# msh-profile: posix
# msh-run: eval
unset nonesuch
$TEST_SHELL -u -c 'echo $nonesuch' && exit 1
$TEST_SHELL -u -c 'echo $3' && exit 1
$TEST_SHELL -u -c 'var=val ; echo ${var+$nonesuch}' && exit 1
$TEST_SHELL -u -c 'echo $(($nonesuch + 1))' && exit 1
$TEST_SHELL -u -c 'echo $((nonesuch + 1))' && exit 1
$TEST_SHELL -u -c 'echo ${#nonesuch}' && exit 1
echo passed
