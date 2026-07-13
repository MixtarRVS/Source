# msh-category: builtin
# msh-name: set plus o nounset disables unset parameter errors
# msh-profile: posix
set -o nounset
set +o nounset
printf '<%s>\n' "$MISSING"
printf 's=%s\n' "$?"
