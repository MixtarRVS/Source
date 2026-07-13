# msh-category: command-search
# msh-name: hash explicit missing path
# msh-profile: posix
hash ./definitely_missing
printf '<%s>\n' "$?"