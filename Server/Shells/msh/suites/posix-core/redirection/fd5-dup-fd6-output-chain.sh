# msh-category: redirection
# msh-name: fd5 dup fd6 output chain
exec 5>out
exec 6>&5
printf 'x\n' >&6
exec 5>&-
printf 'y\n' >&6
exec 6>&-
{ read A; read B; } < out
printf '<%s/%s>\n' "$A" "$B"
