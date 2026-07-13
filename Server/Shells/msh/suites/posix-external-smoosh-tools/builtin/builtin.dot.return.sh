# msh-source: smoosh/tests/shell/builtin.dot.return.test
# msh-profile: posix
# msh-run: eval
cat >scr <<EOF
echo always
(exit 47)
return
echo never
EOF
. ./scr
[ $? -eq 47 ] || exit 1
echo done