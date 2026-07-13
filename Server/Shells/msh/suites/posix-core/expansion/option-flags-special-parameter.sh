# msh-category: expansion
# msh-name: option flags special parameter
set -f
case $- in
    *f*) printf yes;;
    *) printf no;;
esac
