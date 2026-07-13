# msh-source: smoosh/tests/shell/semantics.var.star.format.test
# msh-profile: posix
# msh-run: eval
sp="s p  aces"
tn=$(printf '%b' 'and\ttabs\n and newlines')
set -- a "$sp" b c "$tn"
IFS=": "
printf '<%s>\n' "${var=$*}"
unset var
unset IFS
printf '<%s>\n' "${var=$*}"
