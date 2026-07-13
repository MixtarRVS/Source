# msh-category: redirection
# msh-name: exec stdin persistence
printf 'ok\n' > in
exec 3<&0
exec < in
read A
exec 0<&3
exec 3<&-
printf $A
