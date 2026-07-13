# msh-category: builtin
# msh-name: direct shift ignores extra operands
set -- a b
shift 1 2
printf 'after:%s:%s\n' $? $#
