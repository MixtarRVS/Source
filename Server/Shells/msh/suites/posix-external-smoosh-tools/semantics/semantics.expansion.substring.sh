# msh-source: smoosh/tests/shell/semantics.expansion.substring.test
# msh-profile: posix
# msh-run: eval
FOO="\\a"
echo ${FOO#*\\}
