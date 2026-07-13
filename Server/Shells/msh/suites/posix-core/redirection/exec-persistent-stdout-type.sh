# msh-category: redirection
# msh-name: exec persistent stdout captures type output
# msh-profile: posix
exec 3>&1
exec >msh_type_out
type printf
exec >&3
exec 3>&-
IFS= read -r line < msh_type_out
printf '%s\n' "$line"
