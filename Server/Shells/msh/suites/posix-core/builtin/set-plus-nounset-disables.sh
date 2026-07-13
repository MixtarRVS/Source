# msh-category: builtin
# msh-name: set plus nounset disables unset parameter errors
# msh-profile: posix
set -u
set +u
printf '<%s>\n' "$MISSING"
printf 's=%s\n' "$?"
