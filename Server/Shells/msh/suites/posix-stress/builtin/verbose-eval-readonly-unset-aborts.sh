# msh-category: builtin
# msh-name: verbose eval readonly unset aborts
# msh-profile: posix
# msh-status: nonzero
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -v
eval 'readonly A=old
unset -v A'; printf after
