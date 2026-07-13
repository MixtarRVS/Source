# msh-category: builtin
# msh-name: pwd logical physical options accepted
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
pwd -L > a
pwd -P > b
printf '<%s>\n' $?
