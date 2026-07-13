# msh-category: builtin
# msh-name: printf backslash c stops all output
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf '%b' 'A\cB' C
printf '<after>\n'
