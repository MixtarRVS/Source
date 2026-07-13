# msh-category: expansion
# msh-name: default word command substitution
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
unset A
printf '<%s>\n' "${A:-$(printf x)}"
