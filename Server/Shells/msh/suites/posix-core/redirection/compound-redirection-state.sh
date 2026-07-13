# msh-category: redirection
# msh-name: compound redirection state
A=outer
{ A=inner; printf $A; } > out
printf :$A:
read B < out
printf $B
