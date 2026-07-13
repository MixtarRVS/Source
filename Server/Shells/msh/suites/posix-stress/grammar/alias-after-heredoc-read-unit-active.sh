# msh-category: grammar
# msh-name: alias after heredoc read unit active
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
alias hi='printf ok'
read X <<EOF
x
EOF
hi
