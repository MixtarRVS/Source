# msh-category: expansion
# msh-name: parameter default empty and set
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
unset A
B=
printf '<%s><%s><%s>\n' "${A:-x}" "${B:-y}" "${B-y}"
