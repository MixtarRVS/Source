# msh-category: builtin
# msh-name: command eval output redirection
command eval 'printf hi' > out
printf 'after:'
read x < out
printf '%s' "$x"
