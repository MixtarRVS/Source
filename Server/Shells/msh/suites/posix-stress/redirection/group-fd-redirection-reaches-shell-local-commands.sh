# msh-category: redirection
# msh-name: group fd redirection reaches shell local commands
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
{ printf A >&8; printf B >&8; } 8>out
read X < out
printf '<%s>\n' "$X"
