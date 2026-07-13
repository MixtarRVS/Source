# msh-category: redirection
# msh-name: here document tab stripping
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
read X <<-EOF
	value
EOF
printf '<%s>\n' "$X"
