# msh-source: smoosh/tests/shell/semantics.backtick.exit.test
# msh-profile: posix
# msh-run: eval
foo=$(trap 'echo bar' EXIT)
echo $foo >&2
