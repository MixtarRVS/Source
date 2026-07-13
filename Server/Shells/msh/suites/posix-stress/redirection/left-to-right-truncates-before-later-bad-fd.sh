# msh-category: redirection
# msh-name: left to right truncates before later bad fd
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
printf old > out
: > out >&9
printf after
read X < out
printf '<%s>\n' "$X"
