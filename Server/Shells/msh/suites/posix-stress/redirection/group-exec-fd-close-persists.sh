# msh-category: redirection
# msh-name: group exec fd close persists
# msh-profile: posix
# msh-status: exact
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
exec 8>out
{ exec 8>&-; }
printf A >&8
printf after
