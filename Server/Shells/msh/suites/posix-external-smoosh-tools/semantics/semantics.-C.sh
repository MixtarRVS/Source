# msh-source: smoosh/tests/shell/semantics.-C.test
# msh-profile: posix
# msh-run: eval
echo >in <<EOF
a one
a two
a one two three
four
EOF

touch out

set -o noclobber
cat <in >out
[ $? -gt 0 ] || exit 2