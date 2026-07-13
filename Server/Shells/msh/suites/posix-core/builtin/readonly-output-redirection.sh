# msh-name: readonly output redirection
# msh-profile: posix
readonly A=1; readonly -p > out; read X Y < out; printf "$X"
