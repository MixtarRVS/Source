# msh-category: builtin
# msh-name: command unset f function
f() { printf bad; }
command unset -f f
f
printf after