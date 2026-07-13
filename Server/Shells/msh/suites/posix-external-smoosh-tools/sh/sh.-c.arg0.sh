# msh-source: smoosh/tests/shell/sh.-c.arg0.test
# msh-profile: posix
# msh-run: eval
cat > scr <<EOF
echo "i am \$0, hear me roar"
EOF
$TEST_SHELL -c '. "$0"' ./scr