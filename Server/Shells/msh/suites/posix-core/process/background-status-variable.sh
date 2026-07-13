# msh-category: process
# msh-name: background status variable
true &
pid=$!
wait $pid
printf $?
