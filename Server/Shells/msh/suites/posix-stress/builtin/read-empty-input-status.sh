# msh-category: builtin
# msh-name: read empty input status
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
: > in
read A < in
printf '<%s><%s>\n' "$?" "$A"
