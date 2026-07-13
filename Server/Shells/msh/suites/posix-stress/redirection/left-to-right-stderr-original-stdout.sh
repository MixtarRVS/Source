# msh-category: redirection
# msh-name: left to right stderr original stdout
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
{ printf out; printf err >&2; } 2>&1 >out
read X < out
printf '<%s>\n' "$X"
