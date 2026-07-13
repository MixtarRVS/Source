# msh-category: expansion
# msh-name: readonly parameter assign unset aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
readonly A
printf '<%s>\n' "${A:=value}"
printf after
