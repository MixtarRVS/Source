# msh-category: builtin
# msh-name: export p extra operand output
export A=1
export -p A | read line
printf '<%s>' "$line"