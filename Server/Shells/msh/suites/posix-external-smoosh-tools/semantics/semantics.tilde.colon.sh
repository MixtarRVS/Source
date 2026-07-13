# msh-source: smoosh/tests/shell/semantics.tilde.colon.test
# msh-profile: posix
# msh-run: eval
tilde=~
cat << EOF >test_script
var=:~
[ "\$var" = ":$tilde" ]
EOF
chmod +x test_script
$TEST_SHELL test_script