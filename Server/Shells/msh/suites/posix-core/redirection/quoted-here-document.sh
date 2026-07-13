# msh-name: quoted here document
# msh-profile: posix
A=bad; read B <<'EOF'
$A
EOF
printf $B
