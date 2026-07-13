# msh-category: builtin
# msh-name: eval output redirection is not stdout leak
eval 'printf hi' > out
printf 'after:'
read x < out
printf '%s' "$x"
