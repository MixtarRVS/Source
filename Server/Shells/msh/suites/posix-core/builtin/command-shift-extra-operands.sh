# msh-category: builtin
# msh-name: command shift ignores extra operands
set -- a b
command shift 1 2
printf 'after:%s:%s\n' $? $#
