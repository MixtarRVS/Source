# msh-name: dash here document
# msh-profile: posix
read B <<-EOF
	good
EOF
printf $B
