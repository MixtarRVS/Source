# msh-category: process
# msh-name: command substitution local exit trap runs
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
foo=$(trap 'echo bar' EXIT)
printf '[%s]\n' "$foo"
