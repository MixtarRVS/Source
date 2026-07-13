# msh-category: grammar
# msh-name: while compound input redirection
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
printf 'a\nb\n' > in
while read X; do
    printf '<%s>' "$X"
done < in
printf '\n'
