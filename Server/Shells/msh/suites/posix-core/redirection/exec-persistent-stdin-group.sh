# msh-profile: posix
printf 'one\ntwo\n' > in
exec < in
{
    read a
}
read b
printf '%s:%s\n' "$a" "$b"
