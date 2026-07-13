# msh-source: smoosh/tests/shell/semantics.var.alt.nullifs.test
# msh-profile: posix
# msh-run: eval
IFS=
printf '<%s>\n' ${x+uhoh} a b

f() { echo $#; printf '<%s>\n' "$@" ; }
f ${x+uhoh} a b

x=hi
f ${x+uhoh} a b

