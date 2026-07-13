# msh-source: smoosh/tests/shell/sh.file.weirdness.test
# msh-profile: posix
# msh-run: eval
$TEST_SHELL nonesuch
printf '%s\n' 'echo works' >scr
$TEST_SHELL scr
$TEST_SHELL ./scr
