# msh-category: process
# msh-name: wait true background
true &
wait $!
printf $?
