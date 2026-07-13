printf 'a\\b c\n' > in
IFS=' '
read -r A B < in
printf '<%s><%s>\n' "$A" "$B"
