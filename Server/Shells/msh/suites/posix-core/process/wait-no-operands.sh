# msh-category: process
# msh-name: wait no operands
false &
true &
wait
printf $?
