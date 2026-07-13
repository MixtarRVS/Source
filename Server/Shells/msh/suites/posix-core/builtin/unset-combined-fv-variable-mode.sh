# msh-category: builtin
# msh-name: unset combined fv variable mode
f() { printf bad; }
unset -fv f
f
printf after