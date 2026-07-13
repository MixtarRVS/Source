# msh-category: builtin
# msh-name: type function
f() { :; }
type f >/dev/null
printf $?
