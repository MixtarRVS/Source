# msh-source: smoosh/tests/shell/semantics.background.nojobs.stdin.test
# msh-profile: posix
# msh-run: eval
printf '%s\n' 'set +m' 'exec <in' 'read ignored &' 'wait' 'read parent' 'printf "%s\n" "$parent"' >scr
printf '%s\n' illegible >in
$TEST_SHELL scr
