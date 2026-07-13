# msh-source: smoosh/tests/shell/builtin.exec.modernish.mkfifo.loop.test
# msh-profile: posix
# msh-run: eval
[ -e pipe ] && rm pipe
mkfifo pipe
( echo hello >&8 ) 8>pipe &
command exec 8<pipe
read -r line <&8 ; echo $?
echo read [${line-UNSET}]