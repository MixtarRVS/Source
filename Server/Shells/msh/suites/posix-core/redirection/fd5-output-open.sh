# msh-category: redirection
# msh-name: fd5 output open
exec 5>out
printf 'x\n' >&5
exec 5>&-
read A < out
printf '<%s>\n' "$A"
