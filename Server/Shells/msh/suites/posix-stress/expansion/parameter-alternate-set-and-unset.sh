# msh-category: expansion
# msh-name: parameter alternate set and unset
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=1
unset B
printf '<%s><%s>\n' "${A:+yes}" "${B:+no}"
