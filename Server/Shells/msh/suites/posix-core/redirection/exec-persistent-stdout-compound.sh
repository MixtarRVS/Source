# msh-profile: posix
exec 3>&1
exec > out
{ printf 'group\n'; }
exec >&3
exec 3>&-
read x < out
printf '%s\n' "$x"