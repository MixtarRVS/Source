# msh-source: smoosh/tests/shell/semantics.splitting.ifs.test
# msh-profile: posix
# msh-run: eval
IFS="-,"
echo `printf '%s\n' '-,1-,-2,-,3,-'`
