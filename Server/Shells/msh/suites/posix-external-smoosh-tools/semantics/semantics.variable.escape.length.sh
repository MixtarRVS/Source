# msh-source: smoosh/tests/shell/semantics.variable.escape.length.test
# msh-profile: posix
# msh-run: eval
x=\n
echo ${#x}
x=\\n
echo ${#x}
