# msh-category: builtin
# msh-name: cd dash outputs new pwd
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
pwd > start
mkdir -p d
cd d
cd - > got
read A < start
read B < got
case "$B" in
    "$A") printf ok;;
    *) printf bad;;
esac
