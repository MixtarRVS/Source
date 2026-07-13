# msh-category: redirection
# msh-name: fd5 input open shared offset
printf 'a\nb\n' > in
exec 5<in
read A <&5
read B <&5
printf '<%s/%s>\n' "$A" "$B"
exec 5<&-
