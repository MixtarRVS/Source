# msh-category: redirection
# msh-name: exec persistent stdout captures alias output
# msh-profile: posix
exec 3>&1
alias aa='printf aa'
exec >msh_alias_out
alias aa
exec >&3
exec 3>&-
IFS= read -r line < msh_alias_out
printf '%s\n' "$line"
