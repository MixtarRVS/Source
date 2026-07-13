# msh-category: builtin
# msh-name: wait all background jobs
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
false &
wait
printf '<%s>\n' "$?"
