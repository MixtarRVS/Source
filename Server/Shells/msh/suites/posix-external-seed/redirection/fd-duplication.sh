exec 8> out
printf 'A\n' >&8
exec 9>&8
printf 'B\n' >&9
exec 8>&-
exec 9>&-
while IFS= read -r L; do printf '<%s>' "$L"; done < out
printf '\n'
