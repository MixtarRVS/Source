# msh-category: expansion
# msh-name: parameter assign mutates state
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
unset A
printf '<%s>' "${A:=value}"
printf '<%s>\n' "$A"
