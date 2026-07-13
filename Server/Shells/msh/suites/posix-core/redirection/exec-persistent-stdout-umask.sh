# msh-category: redirection
# msh-name: exec persistent stdout captures umask output
# msh-profile: posix
exec 3>&1
umask 022
exec >msh_umask_out
umask
exec >&3
exec 3>&-
IFS= read -r line < msh_umask_out
printf '%s\n' "$line"
