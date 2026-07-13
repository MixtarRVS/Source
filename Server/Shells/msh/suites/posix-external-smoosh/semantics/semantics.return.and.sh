# msh-source: smoosh/tests/shell/semantics.return.and.test
# msh-profile: posix
# msh-run: eval
f() {
  return 5 && echo fail passthrough
}
f
echo $?

