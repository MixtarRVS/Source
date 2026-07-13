# msh-category: builtin
# msh-name: read temporary same-name assignment restoration
printf 'readval\n' > in
A=assign read A < in
printf 'A=<%s> s=%s\n' "$A" "$?"
