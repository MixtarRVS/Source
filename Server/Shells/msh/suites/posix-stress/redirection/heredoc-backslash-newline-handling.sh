# msh-category: redirection
# msh-name: heredoc backslash newline handling
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
read X <<EOF
a\
b
EOF
printf '<%s>\n' "$X"
