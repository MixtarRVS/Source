# msh-category: redirection
# msh-name: fd7 dup fd6 output chain
exec 6>out
exec 7>&6
printf 'x\n' >&7
exec 6>&-
printf 'y\n' >&7
exec 7>&-
{ read A; read B; } < out
printf '<%s/%s>\n' "$A" "$B"
