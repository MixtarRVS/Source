# msh-name: append redirection
# msh-profile: posix
printf a > out; printf b >> out; read A < out; printf $A
