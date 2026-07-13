# msh-category: grammar
# msh-name: nested case inside function loop
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
f() {
    for x in "$@"; do
        case "$x" in
            a*) printf A;;
            b*) printf B;;
            *) printf Z;;
        esac
    done
}
f ax by cz
