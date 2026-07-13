# msh-category: redirection
# msh-name: command eval redirected output
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
command eval 'printf A' > out
read X < out
printf '<%s>\n' "$X"
