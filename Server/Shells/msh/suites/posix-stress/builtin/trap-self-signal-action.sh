# msh-category: builtin
# msh-name: trap self signal action
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
trap 'printf T' USR1
kill -USR1 $$
printf A
