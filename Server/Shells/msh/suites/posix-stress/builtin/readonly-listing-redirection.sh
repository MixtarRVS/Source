# msh-category: builtin
# msh-name: readonly listing redirection
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
readonly A=1
readonly -p > out
read X < out
case "$X" in
    *A*) printf ok;;
    *) printf bad;;
esac
