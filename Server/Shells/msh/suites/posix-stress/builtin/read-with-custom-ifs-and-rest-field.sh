# msh-category: builtin
# msh-name: read with custom ifs and rest field
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'a:b:c\n' > in
IFS=:
read A B < in
printf '<%s><%s>\n' "$A" "$B"
