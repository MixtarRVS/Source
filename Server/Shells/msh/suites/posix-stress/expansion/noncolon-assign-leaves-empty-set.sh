# msh-category: expansion
# msh-name: noncolon assign leaves empty set
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=
printf '<%s>' "${A=x}"
printf '<%s>\n' "$A"
