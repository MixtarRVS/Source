# msh-source: smoosh/tests/shell/semantics.for.readonly.test
# msh-profile: posix
# msh-run: eval
# ADDTOPOSIX
(for x in a b c; do echo $x; readonly x; done) && exit 1
exit 0
