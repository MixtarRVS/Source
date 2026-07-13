# msh-category: builtin
# msh-name: command eval shift error is nonfatal
set -- a
command eval 'shift 2'
printf 'after\n'
