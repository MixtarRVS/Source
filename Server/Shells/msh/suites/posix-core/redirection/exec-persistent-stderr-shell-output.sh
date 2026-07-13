# msh-category: redirection
# msh-name: exec persistent stderr captures shell local fd2 output
exec 3>&2
exec 2>err
printf err >&2
exec 2>&3
exec 3>&-
read A < err
printf '%s' "$A"
