# msh-source: smoosh/tests/shell/semantics.ifs.combine.ws.test
# msh-profile: posix
# msh-run: eval
unset IFS
echo `printf '%b' '\n\tx\n\n          5\n 12\t '`
IFS=$(printf '%b' ' \n\t')
echo `printf '%b' '\n\tx\n\n          5\n 12\t '`
