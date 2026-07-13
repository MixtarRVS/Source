# msh-source: smoosh/tests/shell/builtin.kill.signame.test
# msh-profile: posix
# msh-run: eval
set -e
seen=0
trap 'seen=1' TERM
kill $$
[ "$seen" -eq 1 ] || exit 1
echo plain kill

seen=0
kill -TERM $$
[ "$seen" -eq 1 ] || exit 2
echo named \(-TERM\)

seen=0
kill -15 $$
[ "$seen" -eq 1 ] || exit 3
echo numbered \(-15\)
