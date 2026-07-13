# msh-source: smoosh/tests/shell/semantics.redir.close.test
# msh-profile: posix
# msh-run: eval
# https://www.spinics.net/lists/dash/msg01775.html
{ exec 8</dev/null; } 8<&-; : <&8 && echo "oops, still open"
