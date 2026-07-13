# msh-name: group read pipeline output
# msh-profile: posix
printf 'a\n' | { read x; printf [$x]; }
