# msh-category: builtin
# msh-name: unset f function
f() { printf bad; }
unset -f f
f
printf after