# msh-category: expansion
# msh-name: arithmetic parameter expands to variable name
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=B
B=4
printf '<%s>\n' "$(( $A + 1 ))"
