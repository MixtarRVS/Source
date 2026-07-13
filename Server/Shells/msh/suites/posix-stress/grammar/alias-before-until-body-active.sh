# msh-category: grammar
# msh-name: alias before until body active
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
alias hi='printf ok'
until false; do
    hi
    break
done
