# msh-category: grammar
# msh-name: alias before while body active
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
alias hi='printf ok'
while true; do
    hi
    break
done
