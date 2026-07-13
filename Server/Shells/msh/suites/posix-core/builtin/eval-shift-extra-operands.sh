# msh-category: builtin
# msh-name: eval shift ignores extra operands
set -- a b
eval 'shift 1 2'
printf 'after:%s:%s\n' $? $#
