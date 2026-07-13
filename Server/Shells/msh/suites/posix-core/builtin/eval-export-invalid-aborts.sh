# msh-category: builtin
# msh-name: eval export invalid aborts
eval 'export 1BAD=x'
printf 'after\n'
