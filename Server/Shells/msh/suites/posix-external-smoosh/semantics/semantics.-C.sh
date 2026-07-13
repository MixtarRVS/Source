# msh-source: smoosh/tests/shell/semantics.-C.test
# msh-profile: posix
# msh-run: eval
: >out
set -o noclobber
printf x >out
[ $? -gt 0 ] || exit 2
