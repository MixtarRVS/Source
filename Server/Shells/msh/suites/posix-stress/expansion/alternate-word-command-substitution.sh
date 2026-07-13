# msh-category: expansion
# msh-name: alternate word command substitution
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=1
unset B
printf '<%s><%s>\n' "${A:+$(printf yes)}" "${B:+$(printf no)}"
