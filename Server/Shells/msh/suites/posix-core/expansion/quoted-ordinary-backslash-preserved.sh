# msh-category: expansion
# msh-name: quoted ordinary backslash survives echo and printf b decoding
# msh-profile: posix
echo '\[]'
echo "\[]"
printf '%b\n' '\[]'
printf '%b\n' "\q"