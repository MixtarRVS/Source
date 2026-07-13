# msh-category: redirection
# msh-name: subshell fd close isolation
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
exec 8>out
(exec 8>&-)
printf A >&8
exec 8>&-
read X < out
printf '<%s>\n' "$X"
