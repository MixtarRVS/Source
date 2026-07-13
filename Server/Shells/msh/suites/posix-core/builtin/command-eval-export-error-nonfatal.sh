# msh-category: builtin
# msh-name: command eval export error is nonfatal
command eval 'export 1bad=2'
printf 'after\n'
