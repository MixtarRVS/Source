# msh-source: smoosh/tests/shell/semantics.tilde.colon.test
# msh-profile: posix
# msh-run: eval
tilde=~
printf 'var=:~\n[ "$var" = ":%s" ]\n' "$tilde" >test_script
$TEST_SHELL test_script
