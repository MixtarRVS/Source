# msh-category: grammar
# msh-name: alias before function body active
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
alias hi='printf ok'
f() { hi; }
f
