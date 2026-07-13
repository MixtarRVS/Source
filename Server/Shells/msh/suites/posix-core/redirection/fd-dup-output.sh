# msh-category: redirection
# msh-name: fd dup output
exec 3>&1
printf ok >&3
exec 3>&-
