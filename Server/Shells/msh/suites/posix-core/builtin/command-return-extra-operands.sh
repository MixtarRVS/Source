# msh-category: builtin
# msh-name: command return extra operands
f(){ command return 3 4; printf bad; }
f
printf 'after:%s\n' $?
