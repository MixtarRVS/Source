# msh-category: builtin
# msh-name: function return status
f() { return 5; printf bad; }
f
printf $?
