# msh-category: grammar
# msh-name: redirection before command name
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
> out printf A
read X < out
printf '<%s>\n' "$X"
