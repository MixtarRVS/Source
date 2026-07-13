# msh-category: expansion
# msh-name: parameter length in quoted word
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=abcd
printf '<%s>\n' "len=${#A}"
