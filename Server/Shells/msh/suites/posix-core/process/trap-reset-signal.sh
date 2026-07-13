# msh-profile: posix
# msh-status: nonzero
trap 'printf trapped\n' TERM
trap - TERM
kill -TERM $$
printf 'after\n'