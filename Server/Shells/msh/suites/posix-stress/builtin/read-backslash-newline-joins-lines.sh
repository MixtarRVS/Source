# msh-category: builtin
# msh-name: read backslash newline joins lines
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf '%s\n%s\n' 'a\' 'b' > in
read X < in
printf '<%s>\n' "$X"
