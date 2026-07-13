# msh-category: builtin
# msh-name: invalid trap signal status is one
# msh-profile: posix
# msh-stderr: normalized
trap cleanup SIGINT
printf '<%s>' "$?"