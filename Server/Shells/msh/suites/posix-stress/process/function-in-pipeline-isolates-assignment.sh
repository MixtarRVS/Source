# msh-category: process
# msh-name: function in pipeline isolates assignment
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=outer
f() { A=inner; printf x; }
f | read X
printf '<%s><%s>\n' "$X" "$A"
