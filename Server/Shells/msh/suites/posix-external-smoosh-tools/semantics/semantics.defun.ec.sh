# msh-source: smoosh/tests/shell/semantics.defun.ec.test
# msh-profile: posix
# msh-run: eval
# ADDTOPOSIX
false
f() { echo hi ; }
echo $?
f

false
f() { echo hello ; }
echo $?
f