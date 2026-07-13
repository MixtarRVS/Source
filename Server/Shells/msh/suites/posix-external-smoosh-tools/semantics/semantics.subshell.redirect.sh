# msh-source: smoosh/tests/shell/semantics.subshell.redirect.test
# msh-profile: posix
# msh-run: eval
# Ensure that the exit trap is ran with the redirections still active.
(trap 'echo foo' EXIT) >/dev/null
