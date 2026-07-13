# msh-source: smoosh/tests/shell/builtin.readonly.assign.interactive.test
# msh-profile: posix
# msh-run: eval
cat >scr <<'EOF'
foo=bar
readonly -- foo
readonly -- baz=quux
echo $foo $baz >&3
foo=nope
unset baz
echo $foo $baz >&3
EOF
exec 3>&1 1>/dev/null 2>/dev/null
$TEST_SHELL -i scr