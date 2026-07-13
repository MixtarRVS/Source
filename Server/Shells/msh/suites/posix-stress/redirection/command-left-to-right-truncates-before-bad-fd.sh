# msh-category: redirection
# msh-name: command left to right truncates before bad fd
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
printf old > out
command : > out >&9
printf after
read X < out
printf '<%s>\n' "$X"
