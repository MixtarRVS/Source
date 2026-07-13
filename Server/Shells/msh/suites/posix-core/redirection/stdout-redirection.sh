# msh-name: stdout redirection
# msh-profile: posix
printf ok > out; read A < out; printf $A
