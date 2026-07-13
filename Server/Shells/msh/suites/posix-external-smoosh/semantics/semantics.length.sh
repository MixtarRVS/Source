# msh-source: smoosh/tests/shell/semantics.length.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01749.html
v=abc; echo ab${#v}cd
