# msh-category: builtin
# msh-name: export assignment visible to command
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
export A=seen
printf '<%s>\n' "$A"
