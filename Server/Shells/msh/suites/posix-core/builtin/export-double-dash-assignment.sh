# msh-category: builtin
# msh-name: export accepts double dash before assignment
# msh-profile: posix
export -- A=1
printf '<%s:%s>' "$A" "$?"