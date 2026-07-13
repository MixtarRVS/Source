# msh-category: process
# msh-name: function return status
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
f() { return 6; }
f
printf '<%s>\n' "$?"
