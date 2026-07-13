# msh-category: builtin
# msh-name: command combined pV default path lookup
# msh-profile: posix
PATH=.
command -pV sh
printf 's=%s\n' "$?"