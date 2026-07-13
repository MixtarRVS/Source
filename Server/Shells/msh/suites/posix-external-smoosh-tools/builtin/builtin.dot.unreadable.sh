# msh-source: smoosh/tests/shell/builtin.dot.unreadable.test
# msh-profile: posix
# msh-run: eval
set -e

echo echo yes >weird
. ./weird

echo echo no >weird
chmod a-r weird
! $TEST_SHELL -c '. ./weird'
rm -f weird
echo done