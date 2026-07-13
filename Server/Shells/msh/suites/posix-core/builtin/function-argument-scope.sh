# msh-category: builtin
# msh-name: function argument scope
set -- global
f() { printf "$1"; }
f local
printf ":$1"
