# msh-category: redirection
# msh-name: append fd preserves existing content
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf X > out
exec 8>>out
printf Y >&8
exec 8>&-
read X < out
printf '<%s>\n' "$X"
