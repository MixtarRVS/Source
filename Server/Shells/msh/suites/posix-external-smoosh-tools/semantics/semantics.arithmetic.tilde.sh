# msh-source: smoosh/tests/shell/semantics.arithmetic.tilde.test
# msh-profile: posix
# msh-run: eval
# bug found in POSIX testing (sh_05.ex tp357)

echo $((~10))