# msh-source: smoosh/tests/shell/builtin.set.quoted.test
# msh-profile: posix
# msh-run: eval
myvar='a b c'
set | grep myvar >scr
. ./scr
printf '%s\n' $myvar
