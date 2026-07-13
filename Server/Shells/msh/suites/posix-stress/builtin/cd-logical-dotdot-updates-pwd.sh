# msh-category: builtin
# msh-name: cd logical dotdot updates pwd
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
pwd > start
mkdir -p d/sub
cd d/sub
cd ..
pwd > now
read A < start
read B < now
case "$B" in
    "$A"/d) printf ok;;
    *) printf bad;;
esac
