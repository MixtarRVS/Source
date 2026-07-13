{ printf 'a\n'; printf 'b\n'; } > out
while IFS= read -r L; do printf '<%s>' "$L"; done < out
printf '\n'
