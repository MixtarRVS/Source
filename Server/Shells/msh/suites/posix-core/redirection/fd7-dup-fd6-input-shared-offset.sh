# msh-category: redirection
# msh-name: fd7 dup fd6 input shared offset
printf 'a\nb\n' > in
exec 6<in
exec 7<&6
read A <&7
read B <&6
printf '<%s/%s>\n' "$A" "$B"
exec 6<&-
exec 7<&-
