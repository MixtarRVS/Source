# msh-category: command-search
# msh-name: hash resolves function
# msh-profile: posix
foo() { :; }
hash foo
printf '<%s>\n' "$?"