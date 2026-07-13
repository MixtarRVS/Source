# msh-category: builtin
# msh-name: command eval exit still exits
command eval 'exit 7'
printf 'after\n'
