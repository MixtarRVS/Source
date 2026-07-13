# msh-category: diagnostic
# msh-name: eval export invalid name stderr
# msh-stderr: normalized
eval 'export 1BAD=x'
printf 'after\n'