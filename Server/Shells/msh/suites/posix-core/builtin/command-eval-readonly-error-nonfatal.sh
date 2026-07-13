# msh-category: builtin
# msh-name: command eval readonly error is nonfatal
command eval 'readonly 1bad=2'
printf 'after\n'
