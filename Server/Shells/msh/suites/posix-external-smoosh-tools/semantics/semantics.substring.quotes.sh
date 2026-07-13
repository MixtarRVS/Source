# msh-source: smoosh/tests/shell/semantics.substring.quotes.test
# msh-profile: posix
# msh-run: eval
FOO="a?b"
[ "${FOO#*"?"}" = b ] && echo OK1
FOO="abc"
[ "${FOO#"${FOO%???}"}" = "$FOO" ] && echo OK2
