# msh-name: export output redirection
# msh-profile: posix
export A=1; export -p > out; read X Y < out; printf "$X"
