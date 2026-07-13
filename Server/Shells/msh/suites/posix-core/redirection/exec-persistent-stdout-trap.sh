# msh-category: redirection
# msh-name: exec persistent stdout captures trap output
# msh-profile: posix
exec 3>&1
trap 'printf trapped' TERM
exec >msh_trap_out
trap
exec >&3
exec 3>&-
IFS= read -r line < msh_trap_out
printf '%s\n' "$line"
