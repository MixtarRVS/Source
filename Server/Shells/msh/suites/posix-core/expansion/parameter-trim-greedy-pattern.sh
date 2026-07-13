# msh-profile: posix
x=abcabc
printf '%s\n' "${x#*b}" "${x##*b}" "${x%b*}" "${x%%b*}"