# msh-name: while read pipeline output
# msh-profile: posix
printf 'a\nb\n' | while read x; do printf [$x]; done
