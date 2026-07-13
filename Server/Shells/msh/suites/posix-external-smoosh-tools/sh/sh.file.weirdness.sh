# msh-source: smoosh/tests/shell/sh.file.weirdness.test
# msh-profile: posix
# msh-run: eval
$TEST_SHELL nonesuch
echo 'echo works' >scr
$TEST_SHELL scr
$TEST_SHELL ./scr
echo 'echo nope' >scr
chmod -r scr
$TEST_SHELL ./scr && exit 1
$TEST_SHELL scr && exit 1
rm -f scr

