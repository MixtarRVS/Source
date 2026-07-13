# msh-profile: posix
printf 'a\nb\n' > in
exec 3< in
read x <&3
read y <&3
exec 3<&-
printf '%s:%s\n' "$x" "$y"