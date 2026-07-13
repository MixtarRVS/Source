# msh-category: builtin
# msh-name: test negated file
[ -d . ] && [ ! -f ./msh-missing-file ] && printf ok
