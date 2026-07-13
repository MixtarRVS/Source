# msh-category: expansion
# msh-name: parameter null colon rules
A=; printf ${A-default}:${A:-default}
