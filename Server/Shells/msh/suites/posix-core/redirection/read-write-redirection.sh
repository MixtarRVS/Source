# msh-category: redirection
# msh-name: read write redirection
printf 'old\n' > rw
exec 3<> rw
read A <&3
printf new >&3
exec 3>&-
printf $A
