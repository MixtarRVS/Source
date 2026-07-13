# msh-category: expansion
# msh-name: readonly arithmetic compound assignment aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: normalized
# msh-run: eval
# msh-args: 
A=1
readonly A
printf '<%s>\n' "$((A+=2))"
printf after
