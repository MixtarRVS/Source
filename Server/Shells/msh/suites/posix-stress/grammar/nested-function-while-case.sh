# msh-category: grammar
# msh-name: nested function while case
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
f() {
    while [ $# -gt 0 ]; do
        case "$1" in
            a) printf A;;
            b) printf B;;
        esac
        shift
    done
}
f a b
