# msh-category: expansion
# msh-name: parameter alternate unset
unset A; printf ${A:+yes}:${A:-no}
