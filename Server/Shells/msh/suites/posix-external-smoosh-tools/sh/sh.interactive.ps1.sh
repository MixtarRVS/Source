# msh-source: smoosh/tests/shell/sh.interactive.ps1.test
# msh-profile: posix
# msh-run: eval
echo exit | PS1='$ ' $TEST_SHELL -i
