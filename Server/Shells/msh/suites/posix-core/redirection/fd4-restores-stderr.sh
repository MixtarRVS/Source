# msh-category: redirection
# msh-name: arbitrary fd restores stderr after persistent redirection
exec 4>&2
exec 2>err
printf err >&2
exec 2>&4
exec 4>&-
printf ok >&2
read A < err
printf '%s' "$A"
