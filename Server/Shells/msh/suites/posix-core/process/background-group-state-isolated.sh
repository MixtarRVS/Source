# msh-category: process
# msh-name: background group state isolated
A=old
{ A=new; } &
wait
printf "$A"
