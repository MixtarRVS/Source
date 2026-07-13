# msh-source: smoosh/tests/shell/semantics.error.noninteractive.test
# msh-profile: posix
# msh-run: eval
cat <<EOF > script
unset x
y=z
echo ${x?z}
echo blargh
EOF
chmod +x script
$TEST_SHELL script
