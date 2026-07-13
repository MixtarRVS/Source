# msh-profile: posix
f() { printf 'left\n'; }
f | read x
printf '%s\n' "$x"