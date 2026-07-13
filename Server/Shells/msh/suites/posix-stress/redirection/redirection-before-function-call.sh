# msh-category: redirection
# msh-name: redirection before function call
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
f() { printf A; }
> out f
read X < out
printf '<%s>\n' "$X"
