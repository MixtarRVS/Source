# msh-category: redirection
# msh-name: exec stdout persistence
exec 3>&1
exec > out
printf ok
exec 1>&3
exec 3>&-
read A < out
printf $A
