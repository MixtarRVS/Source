# msh-category: diagnostic
# msh-name: eval readonly invalid name stderr
# msh-stderr: normalized
eval 'readonly 1BAD=x'
printf 'after\n'