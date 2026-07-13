# msh-source: smoosh/tests/shell/semantics.var.unset.nofield.test
# msh-profile: posix
# msh-run: eval
count() { echo $#; }
[ $(count a $nonesuch b) -eq 2 ]