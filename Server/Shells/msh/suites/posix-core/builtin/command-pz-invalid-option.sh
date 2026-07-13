# msh-category: builtin
# msh-name: command combined invalid option reports bad character
# msh-profile: posix
# msh-stderr: normalized
command -pz true
printf 's=%s\n' "$?"