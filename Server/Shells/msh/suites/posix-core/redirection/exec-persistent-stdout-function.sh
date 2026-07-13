# msh-profile: posix
exec 3>&1
exec > out
f() {
    printf 'fn\n'
}
f
exec >&3
exec 3>&-
read x < out
printf '%s\n' "$x"
