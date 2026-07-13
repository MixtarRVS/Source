# msh-category: expansion
# msh-name: command substitution unquoted splitting
set -- $(printf 'a b\n')
printf "$#:$1:$2"
