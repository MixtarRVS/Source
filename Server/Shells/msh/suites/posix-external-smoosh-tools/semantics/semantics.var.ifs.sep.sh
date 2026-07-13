# msh-source: smoosh/tests/shell/semantics.var.ifs.sep.test
# msh-profile: posix
# msh-run: eval
IFS=", "
set 1 2 3
echo "$*"
