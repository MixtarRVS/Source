# msh-category: redirection
# msh-name: fd duplicate output chain
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
exec 8>out
exec 9>&8
printf A >&9
printf B >&8
exec 9>&-
exec 8>&-
read X < out
printf '<%s>\n' "$X"
