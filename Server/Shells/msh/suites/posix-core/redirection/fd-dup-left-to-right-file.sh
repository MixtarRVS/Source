# msh-profile: posix
{ printf out; printf err >&2; } > both 2>&1
read x < both
printf '%s' "$x"