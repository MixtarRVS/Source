# msh-profile: posix
eval 'printf hi' > out
read x < out
printf '%s' "$x"