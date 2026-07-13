# msh-source: smoosh/tests/shell/semantics.var.alt.null.test
# msh-profile: posix
# msh-run: eval
f() { echo $# ; }
unset -v nonesuch
f ${nonesuch+nonempty} a b

x=foo
f ${x+hi} a b
