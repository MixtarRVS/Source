# msh-category: builtin
# msh-name: command double dash executes builtin
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf() { :; }
command -- printf 'ok\n'
