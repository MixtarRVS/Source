# msh-source: smoosh/tests/shell/semantics.background.nojobs.stdin.test
# msh-profile: posix
# msh-run: eval
cat >scr <<EOF
set +m
exec <in
cat &
wait
EOF

echo illegible >in
$TEST_SHELL scr
