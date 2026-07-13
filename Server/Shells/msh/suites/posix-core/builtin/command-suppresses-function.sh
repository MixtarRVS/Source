# msh-category: builtin
# msh-name: command suppresses function
false() { return 0; }
command false
printf $?
