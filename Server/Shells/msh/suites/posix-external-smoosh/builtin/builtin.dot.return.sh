# msh-source: smoosh/tests/shell/builtin.dot.return.test
# msh-profile: posix
# msh-run: eval
printf '%s\n' 'echo always' '(exit 47)' 'return' 'echo never' >scr
. ./scr
[ $? -eq 47 ] || exit 1
echo done
