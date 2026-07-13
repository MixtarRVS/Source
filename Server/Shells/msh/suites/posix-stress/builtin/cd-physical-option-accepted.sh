# msh-category: builtin
# msh-name: cd physical option accepted
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
cd -P .
printf '<%s>\n' $?
