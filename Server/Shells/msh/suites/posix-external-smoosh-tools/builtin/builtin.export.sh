# msh-source: smoosh/tests/shell/builtin.export.test
# msh-profile: posix
# msh-run: eval
cat >scr <<'EOF'
echo ${var-unset}
EOF
$TEST_SHELL scr
var=hi
$TEST_SHELL scr
var=here $TEST_SHELL scr
export var=bye
$TEST_SHELL scr
