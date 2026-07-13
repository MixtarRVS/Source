# msh-source: smoosh/tests/shell/builtin.source.nonexistent.earlyexit.test
# msh-profile: posix
# msh-run: eval
source not_a_thing
echo hi
exit 0