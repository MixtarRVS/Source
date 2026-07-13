# msh-source: smoosh/tests/shell/semantics.noninteractive.expansion.exit.test
# msh-profile: posix
# msh-run: eval
unset x
echo ${x?alas, poor yorick}
