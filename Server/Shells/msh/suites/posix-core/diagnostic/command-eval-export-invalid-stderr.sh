# msh-category: diagnostic
# msh-name: command eval export invalid name stderr
# msh-stderr: normalized
command eval 'export 1BAD=x'
printf 'after\n'