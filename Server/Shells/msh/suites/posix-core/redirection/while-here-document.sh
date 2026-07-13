# msh-name: while here document
# msh-profile: posix
while read x; do printf [$x]; done <<EOF
a
b
EOF
