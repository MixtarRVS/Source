# msh-category: builtin
# msh-name: read final var preserves separators
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'a:b:c:d\n' > in
IFS=:
read A B < in
printf '<%s><%s>\n' "$A" "$B"
