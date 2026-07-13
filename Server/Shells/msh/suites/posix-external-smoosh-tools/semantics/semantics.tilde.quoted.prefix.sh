# msh-source: smoosh/tests/shell/semantics.tilde.quoted.prefix.test
# msh-profile: posix
# msh-run: eval
# ADDTOPOSIX

set -e
tilde=$(echo ~)
[ "$tilde" = "$HOME" ] || exit 1

funny='~'\""$LOGNAME"\"
exp=$(eval "echo $funny")
[ "$exp" = "~$LOGNAME" ] || exit 2

[ ~/ = "$HOME"/ ] || exit 3

echo ok