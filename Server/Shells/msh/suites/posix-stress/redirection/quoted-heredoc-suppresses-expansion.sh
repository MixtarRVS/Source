# msh-category: redirection
# msh-name: quoted heredoc suppresses expansion
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
A=value
read X <<'EOF'
$A
EOF
printf '<%s>\n' "$X"
