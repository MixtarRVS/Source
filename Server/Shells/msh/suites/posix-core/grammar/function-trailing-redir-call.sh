# msh-profile: posix
f() { printf 'inside\n'; } > out
f
read x < out
printf '%s\n' "$x"