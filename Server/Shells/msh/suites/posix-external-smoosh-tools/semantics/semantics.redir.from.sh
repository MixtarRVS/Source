# msh-source: smoosh/tests/shell/semantics.redir.from.test
# msh-profile: posix
# msh-run: eval
set -e
echo hi >file
[ -s file ]
read x <file
[ "$x" = "hi" ]
rm file