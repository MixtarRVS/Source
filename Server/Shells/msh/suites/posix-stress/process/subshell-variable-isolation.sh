# msh-category: process
# msh-name: subshell variable isolation
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=parent
(A=child; printf '<%s>' "$A")
printf '<%s>\n' "$A"
