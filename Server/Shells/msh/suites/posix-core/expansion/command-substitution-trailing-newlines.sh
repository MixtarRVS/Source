# msh-category: expansion
# msh-name: command substitution trailing newlines
A=$(printf 'a\n\n')
printf "$A"
