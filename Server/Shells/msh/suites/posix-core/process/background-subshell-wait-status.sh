# msh-profile: posix
(exit 7) &
p=$!
wait "$p"
printf '%s\n' "$?"