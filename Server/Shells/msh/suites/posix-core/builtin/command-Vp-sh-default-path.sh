# msh-category: builtin
# msh-name: command combined Vp default path lookup
# msh-profile: posix
PATH=.
command -Vp sh
printf 's=%s\n' "$?"