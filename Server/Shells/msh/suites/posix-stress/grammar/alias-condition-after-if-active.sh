# msh-category: grammar
# msh-name: alias condition after if active
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
alias yes='true'
if yes; then printf ok; fi
