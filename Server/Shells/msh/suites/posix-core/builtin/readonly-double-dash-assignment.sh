# msh-category: builtin
# msh-name: readonly accepts double dash before assignment
# msh-profile: posix
readonly -- A=1
printf '<%s:%s>' "$A" "$?"