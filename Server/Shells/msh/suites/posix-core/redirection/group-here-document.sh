# msh-name: group here document
# msh-profile: posix
{ read x; printf [$x]; } <<EOF
a
EOF
