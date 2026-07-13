# msh-category: process
# msh-name: wait false background status
false &
wait $!
printf $?
