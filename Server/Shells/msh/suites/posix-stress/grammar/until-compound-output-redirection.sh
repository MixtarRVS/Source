# msh-category: grammar
# msh-name: until compound output redirection
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
i=0
until [ "$i" -ge 2 ]; do
    i=$((i+1))
    printf "$i"
done > out
read X < out
printf '<%s>\n' "$X"
