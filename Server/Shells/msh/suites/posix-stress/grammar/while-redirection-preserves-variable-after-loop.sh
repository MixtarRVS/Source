# msh-category: grammar
# msh-name: while redirection preserves variable after loop
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'a\nb\n' > in
last=
while read x; do
    last=$x
done < in
printf '<%s>\n' "$last"
