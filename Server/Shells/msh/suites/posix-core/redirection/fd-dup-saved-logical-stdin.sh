# msh-category: redirection
# msh-name: fd dup saved logical stdin
printf 'A\nB\nC\n' > in
exec < in
exec 3<&0
read A
read B <&3
read C
printf '%s:%s:%s\n' "$A" "$B" "$C"
