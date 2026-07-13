# msh-category: redirection
# msh-name: fd dup saved logical stdout
exec 4>&1
exec > out
exec 3>&1
printf 'A\n'
exec > out2
printf 'B\n' >&3
exec >&4
exec < out
read A
read B
exec < out2
read C
printf "$A:$B:$C"
