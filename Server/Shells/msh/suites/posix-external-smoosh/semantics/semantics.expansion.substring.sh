# msh-source: smoosh/tests/shell/semantics.expansion.substring.test
# msh-profile: posix
# msh-run: file
FOO="\\a"
echo ${FOO#*\\}
