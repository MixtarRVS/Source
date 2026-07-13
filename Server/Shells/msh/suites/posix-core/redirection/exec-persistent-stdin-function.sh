# msh-profile: posix
printf 'one\ntwo\n' > in
exec < in
f() {
    read a
}
f
read b
printf '%s:%s\n' "$a" "$b"
