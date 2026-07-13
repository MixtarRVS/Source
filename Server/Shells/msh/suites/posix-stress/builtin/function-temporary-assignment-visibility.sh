# msh-category: builtin
# msh-name: function temporary assignment visibility
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=outer
f() { printf '<%s>' "$A"; }
A=inner f
printf '<%s>\n' "$A"
