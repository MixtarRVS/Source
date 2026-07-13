# msh-profile: posix
exec 3> out
printf 'hi\n' >&3
exec 3>&-
read x < out
printf '%s\n' "$x"