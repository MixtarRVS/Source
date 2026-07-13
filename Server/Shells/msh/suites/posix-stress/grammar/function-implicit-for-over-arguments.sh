# msh-category: grammar
# msh-name: function implicit for over arguments
# msh-profile: posix
# msh-status: exact
# msh-stderr: off
# msh-run: eval
# msh-args: 
set -- ax by
f() {
    for x
    do
        case "$x" in
            a*) printf A;;
            b*) printf B;;
        esac
    done
}
f "$@"
