# msh-category: builtin
# msh-name: eval readonly invalid aborts
eval 'readonly 1BAD=x'
printf 'after\n'
