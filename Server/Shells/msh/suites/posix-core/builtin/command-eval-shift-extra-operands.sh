# msh-category: builtin
# msh-name: command eval shift ignores extra operands
set -- a b
command eval 'shift 1 2'
printf 'after:%s:%s\n' $? $#
