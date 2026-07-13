# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
cat <<EOF > script
unset x
y=z
echo ${x?z}
echo blargh
EOF
chmod +x script
$TEST_SHELL script
