# msh-category: builtin
# msh-name: read raw backslash newline does not join
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf '%s\n%s\n' 'a\' 'b' > in
read -r X < in
printf '<%s>\n' "$X"
