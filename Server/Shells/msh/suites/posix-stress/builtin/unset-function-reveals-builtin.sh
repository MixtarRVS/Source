# msh-category: builtin
# msh-name: unset function reveals builtin
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf() { :; }
unset -f printf
printf ok
