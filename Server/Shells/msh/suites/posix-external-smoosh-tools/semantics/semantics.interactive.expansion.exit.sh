# msh-source: smoosh/tests/shell/semantics.interactive.expansion.exit.test
# msh-profile: posix
# msh-run: eval
PS1="" $TEST_SHELL -i -c 'echo ${x?alas, poor yorick}; echo hello; exit'
