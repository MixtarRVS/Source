# msh-category: diagnostic
# msh-name: trap invalid signal stderr
# msh-stderr: normalized
trap - BAD
printf 'after\n'