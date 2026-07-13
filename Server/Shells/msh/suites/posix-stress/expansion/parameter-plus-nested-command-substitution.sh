# msh-category: expansion
# msh-name: parameter plus nested command substitution
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=1
printf '<%s>\n' "${A:+$(printf 'x y')}"
