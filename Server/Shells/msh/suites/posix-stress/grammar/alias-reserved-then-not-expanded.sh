# msh-category: grammar
# msh-name: alias reserved then not expanded
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
alias then='printf bad'
if true; then printf ok; fi
