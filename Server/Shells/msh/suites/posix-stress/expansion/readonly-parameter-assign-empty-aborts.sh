# msh-category: expansion
# msh-name: readonly parameter assign empty aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
A=
readonly A
printf '<%s>\n' "${A:=value}"
printf after
