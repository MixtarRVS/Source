# msh-source: smoosh/tests/shell/semantics.return.not.test
# msh-profile: posix
# msh-run: eval
f() {
  ! return 5
  echo fail passthrough
}
f
echo $?

