# msh-category: redirection
# msh-name: exec duplicate stdout before retarget
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
exec 8>&1
printf A >&8 >out
read X < out
printf '<%s>\n' "$X"
