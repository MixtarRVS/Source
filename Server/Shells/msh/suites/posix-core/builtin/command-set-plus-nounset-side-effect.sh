# msh-category: builtin
# msh-name: command set plus nounset keeps option side effect
# msh-profile: posix
set -u
command set +u
printf '<%s>\n' "$MISSING"
printf 's=%s\n' "$?"
