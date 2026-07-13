# msh-category: grammar
# msh-name: alias after bang active
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
alias no='false'
! no
printf ':'
printf "$?"
