# msh-name: EXIT trap preserves quoted status expansion
# msh-profile: posix
trap 'printf exit:%s "$?"' EXIT
false
