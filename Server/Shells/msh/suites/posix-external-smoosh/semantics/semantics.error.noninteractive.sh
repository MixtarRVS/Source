# msh-source: smoosh/tests/shell/semantics.error.noninteractive.test
# msh-profile: posix
# msh-run: eval
# msh-stderr: normalized
$TEST_SHELL -c 'echo before; ${MSH_UNSET_FOR_ERROR:?z}; echo after'
printf 'status=%s\n' "$?"
