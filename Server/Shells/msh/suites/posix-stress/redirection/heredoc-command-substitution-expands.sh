# msh-category: redirection
# msh-name: heredoc command substitution expands
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
read X <<EOF
$(printf A)
EOF
printf '<%s>\n' "$X"
