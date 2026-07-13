# msh-source: smoosh/tests/shell/builtin.eval.break.test
# msh-profile: posix
# msh-run: eval
for x in a b c; do echo $x; eval break; done
