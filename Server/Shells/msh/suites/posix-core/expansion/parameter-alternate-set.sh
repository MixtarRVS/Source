# msh-category: expansion
# msh-name: parameter alternate set
A=x; printf ${A:+yes}:${A:-no}
