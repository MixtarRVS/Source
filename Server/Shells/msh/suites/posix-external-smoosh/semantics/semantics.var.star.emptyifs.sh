# msh-source: smoosh/tests/shell/semantics.var.star.emptyifs.test
# msh-profile: posix
# msh-run: eval
IFS=""
bee="b  e   e"
set a "$bee" c

printf '<%s>\n' $*
printf '<%s>\n' HI$*BYE
