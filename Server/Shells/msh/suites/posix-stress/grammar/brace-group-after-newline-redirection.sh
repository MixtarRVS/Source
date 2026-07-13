# msh-category: grammar
# msh-name: brace group after newline redirection
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
{
    printf A
    printf B
} > out
read X < out
printf '<%s>\n' "$X"
