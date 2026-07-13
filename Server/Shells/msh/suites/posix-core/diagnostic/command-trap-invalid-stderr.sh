# msh-category: diagnostic
# msh-name: command trap invalid signal stderr
# msh-stderr: normalized
command trap - BAD
printf 'after\n'