# msh-category: builtin
# msh-name: direct return extra operands
f(){ return 3 4; printf bad; }
f
printf 'after:%s\n' $?
