# msh-category: diagnostic
# msh-name: command eval readonly invalid name stderr
# msh-stderr: normalized
command eval 'readonly 1BAD=x'
printf 'after\n'