# msh-source: smoosh/tests/shell/semantics.evalorder.fun.test
# msh-profile: posix
# msh-run: eval
# bash: assign
# yash, dash, smoosh: redir
# ADDTOPOSIX
show() { echo "got ${EFF-unset}"; }
unset x
EFF=${x=assign} show 2>${x=redir}
echo ${EFF-unset after function call}
[ -f assign ] && echo assign exists
[ -f redir ] && echo redir exists
