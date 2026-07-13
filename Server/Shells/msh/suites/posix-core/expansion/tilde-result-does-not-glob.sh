# msh-category: expansion
# msh-name: tilde expansion result is not pathname-expanded
# msh-profile: posix
HOME='a*'
touch a1 a2 a3
printf '%s\n' ~