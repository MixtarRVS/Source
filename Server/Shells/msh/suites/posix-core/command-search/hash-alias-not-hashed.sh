# msh-category: command-search
# msh-name: hash does not resolve alias
# msh-profile: posix
# msh-stderr: normalized
alias foo=true
hash foo
printf '<%s>\n' "$?"