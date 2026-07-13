# msh-source: smoosh/tests/shell/builtin.test.-nt.-ot.absent.test
# msh-profile: posix
# msh-run: eval
touch present
[ present -nt absent ] || exit 1
[ absent -ot present ] || exit 2
