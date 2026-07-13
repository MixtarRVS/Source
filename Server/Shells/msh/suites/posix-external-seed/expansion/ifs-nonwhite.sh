IFS=:
set -- a:b::c
for x in $1; do printf '<%s>' "$x"; done
printf '\n'
