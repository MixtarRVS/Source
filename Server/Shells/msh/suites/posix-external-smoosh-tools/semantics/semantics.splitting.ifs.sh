# msh-source: smoosh/tests/shell/semantics.splitting.ifs.test
# msh-profile: posix
# msh-run: eval
cat << EOF > input
-,1-,-2,-,3,-
EOF

IFS="-,"
echo `cat input`