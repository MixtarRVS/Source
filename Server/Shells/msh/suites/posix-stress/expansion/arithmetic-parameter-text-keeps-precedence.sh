# msh-category: expansion
# msh-name: arithmetic parameter text keeps precedence
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A='1+2*3'
printf '<%s>\n' "$(( $A * 2 ))"
