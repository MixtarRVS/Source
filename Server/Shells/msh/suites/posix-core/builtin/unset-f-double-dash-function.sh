# msh-category: builtin
# msh-name: unset f double dash function
f() { printf bad; }
unset -f -- f
f
printf after