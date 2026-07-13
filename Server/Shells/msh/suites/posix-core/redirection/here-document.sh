# msh-name: here document
# msh-profile: posix
read A <<EOF
ok
EOF
printf $A
