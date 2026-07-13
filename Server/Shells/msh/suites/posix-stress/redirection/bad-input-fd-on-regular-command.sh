# msh-category: redirection
# msh-name: bad input fd on regular command
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
printf ok <&9
printf after
