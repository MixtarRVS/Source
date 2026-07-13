# msh-category: builtin
# msh-name: set options before double dash then positionals
# msh-profile: posix
set -f -- a b
printf '<%s:%s:%s:%s>' "$#" "$1" "$-" "$?"